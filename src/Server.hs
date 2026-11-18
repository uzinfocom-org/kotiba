{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Server (run) where

import API
import Config
import Config.Load (loadConfig)
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (newTQueueIO)
import Control.Exception (SomeException, catch)
import Control.Monad.Except (runExceptT)
import Control.Monad.Logger (runStdoutLoggingT)
import Data.ByteString qualified as BS
import Data.Map qualified as Map
import Data.Text (pattern Empty)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Database.Persist.Postgresql (createPostgresqlPool)
import Database.Seed (seedErrorMessage, seedIfChanged, syncBots)
import Events.Tracking.Worker (worker)
import Forgejo.App (mkAppEnv)
import Kotiba.Prelude
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (hContentType, status500)
import Network.Wai (responseLBS)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Options.Generic
import Servant
import Servant.Client (mkClientEnv, parseBaseUrl)
import System.Exit (ExitCode (..), exitWith)
import System.IO (BufferMode (..), hPutStrLn, hSetBuffering, stderr, stdout)

type Options :: Type -> Type
newtype Options w = Options
  { cfg :: w ::: FilePath <?> "Config file path" <#> "c"
  }
  deriving stock (Generic)

deriving anyclass instance ParseRecord (Options Wrapped)
deriving stock instance Show (Options Unwrapped)

type StartupError :: Type
data StartupError
  = ConfigLoadFailed
  | SecretFileEmpty FilePath

exitFailure :: ExitCode
exitFailure = ExitFailure 78

startupExitCode :: StartupError -> ExitCode
startupExitCode ConfigLoadFailed = exitFailure
startupExitCode (SecretFileEmpty _) = exitFailure

renderStartupError :: StartupError -> String
renderStartupError ConfigLoadFailed = "Failed to load config"
renderStartupError (SecretFileEmpty path) = "Required configuration file '" <> path <> "' is empty."

dieWith :: StartupError -> IO a
dieWith e = hPutStrLn stderr (renderStartupError e) *> exitWith (startupExitCode e)

catchExceptions :: Application -> Application
catchExceptions app req res =
  app req res `catch` \(ex :: SomeException) -> do
    print $ "Unhandled exception: " <> show ex
    res
      $ responseLBS
        status500
        [(hContentType, "application/json")]
        mempty

readNonEmptyFile :: FilePath -> IO (Either StartupError T.Text)
readNonEmptyFile path = nonEmpty . T.strip <$> TIO.readFile path
 where
  nonEmpty Empty = Left (SecretFileEmpty path)
  nonEmpty content = Right content

run :: IO ()
run = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  (op :: Options Unwrapped) <- unwrapRecord "Kotiba application"
  putStrLn "Application ready to start"

  c <- loadConfig defaults op.cfg
  printer c

  pool <- runStdoutLoggingT $ createPostgresqlPool (encodeUtf8 c.database) c.databasePoolSize
  manager <- newTlsManager
  baseUrl <- parseBaseUrl $ T.unpack c.forgejoUrl
  let cenv = mkClientEnv manager baseUrl

  orgEnvs <- flip Map.traverseWithKey c.orgs \name o -> do
    tok <- either dieWith pure =<< readNonEmptyFile o.bot.token
    sec <- BS.readFile o.webhookSecret
    pure
      OrgEnv
        { orgName = T.toLower name
        , orgBot = o.bot
        , orgToken = tok
        , orgWebhookSecret = sec
        , orgForgejo = mkAppEnv cenv ("token" <> tok)
        }

  queue <- newTQueueIO

  let st =
        MkAppSt
          { config = c
          , db = pool
          , trackQueue = queue
          , orgEnvs = orgEnvs
          }
      settings = setPort c.port $ setHost "*" defaultSettings
  migrate' st
  let ?st = st

  sResult <-
    runExceptT $ do
      seedIfChanged st c.seedFile
      syncBots $ map (.bot) (Map.elems c.orgs)

  either (putStrLn . seedErrorMessage) pure sResult

  _ <- forkIO worker
  runSettings settings (catchExceptions runApi)
