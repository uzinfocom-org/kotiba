{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module Server (run) where

import API
import Config (OrgConfig (..), defaults)
import Config.Load (loadConfig)
import Control.Concurrent (forkIO)
import Control.Concurrent.STM (newTQueueIO)
import Control.Exception (SomeException, catch)
import Control.Monad (when)
import Control.Monad.Except (runExceptT)
import Control.Monad.Logger (runStdoutLoggingT)
import Data.Map (Map)
import Data.Map qualified as Map
import Data.Text (pattern Empty)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Data.Traversable (for)
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
import Servant.Client (ClientEnv, mkClientEnv, parseBaseUrl)
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
  = SecretFileEmpty FilePath
  | DuplicateOrgs

exitConfig :: ExitCode
exitConfig = ExitFailure 78

renderStartupError :: StartupError -> String
renderStartupError (SecretFileEmpty path) = "Required configuration file '" <> path <> "' is empty."
renderStartupError DuplicateOrgs = "Names of organizations must be unique, ignoring case."

dieWith :: StartupError -> IO a
dieWith e = hPutStrLn stderr (renderStartupError e) *> exitWith exitConfig

catchExceptions :: Application -> Application
catchExceptions app req res =
  app req res `catch` \(ex :: SomeException) -> do
    hPutStrLn stderr $ "Unhandled exception: " <> show ex
    res
      $ responseLBS
        status500
        [(hContentType, "application/json")]
        mempty

-- | Strips whitespace, so a trailing newline doesn't change a secret.
readNonEmptyFile :: FilePath -> IO (Either StartupError T.Text)
readNonEmptyFile path = nonEmpty . T.strip <$> TIO.readFile path
 where
  nonEmpty Empty = Left (SecretFileEmpty path)
  nonEmpty content = Right content

{- | Reads token and secret of every org and builds its Forgejo client.
All clients share one 'ClientEnv' (so one connection pool).
Names are lowercased because 'lookupOrg' does that too.
Two names that become the same are refused, or one would silently disappear.
-}
mkOrgEnvs :: ClientEnv -> Map Text OrgConfig -> IO (Map Text OrgEnv)
mkOrgEnvs cenv orgCfgs = do
  pairs <- for (Map.toList orgCfgs) \(key, o) -> do
    tok <- either dieWith pure =<< readNonEmptyFile o.bot.token
    sec <- encodeUtf8 <$> (either dieWith pure =<< readNonEmptyFile o.webhookSecret)
    let lowered = T.toLower key
    pure
      ( lowered
      , OrgEnv
          { orgName = lowered
          , orgBot = o.bot
          , orgToken = tok
          , orgWebhookSecret = sec
          , orgForgejo = mkAppEnv cenv ("token " <> tok)
          }
      )
  let envs = Map.fromList pairs
  when (Map.size envs /= length pairs) $ dieWith DuplicateOrgs
  pure envs

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
  orgEnvs <- mkOrgEnvs (mkClientEnv manager baseUrl) c.orgs

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

  -- seed problems are printed but don't stop the start
  sResult <-
    runExceptT $ do
      seedIfChanged st c.seedFile
      syncBots $ map (.bot) (Map.elems c.orgs)

  either (putStrLn . seedErrorMessage) pure sResult

  _ <- forkIO worker
  runSettings settings (catchExceptions runApi)
