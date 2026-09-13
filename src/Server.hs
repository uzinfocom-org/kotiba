{-# LANGUAGE OverloadedStrings #-}

module Server (run) where

import API
import Config
import Control.Exception (SomeException, catch)
import Control.Monad.Logger (runStdoutLoggingT)
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Data.Text.IO qualified as TIO
import Database.Persist.Postgresql (createPostgresqlPool)
import Database.Seed (seedIfChanged)
import Forgejo.App (mkAppEnv)
import Kotiba.Prelude
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (hContentType, status500)
import Network.Wai (responseLBS)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import Options.Generic
import Servant
import Servant.Client (mkClientEnv, parseBaseUrl)
import System.IO (BufferMode (..), hSetBuffering, stderr, stdout)
import Toml.Schema.Matcher (Result (..))

type Options :: Type -> Type
newtype Options w = Options
  { cfg :: w ::: FilePath <?> "Config file path" <#> "c"
  }
  deriving stock (Generic)

deriving anyclass instance ParseRecord (Options Wrapped)
deriving stock instance Show (Options Unwrapped)

catchExceptions :: Application -> Application
catchExceptions app req res =
  app req res `catch` \(ex :: SomeException) -> do
    print $ "Unhandled exception: " <> show ex
    res
      $ responseLBS
        status500
        [(hContentType, "application/json")]
        mempty

run :: IO ()
run = do
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  (op :: Options Unwrapped) <- unwrapRecord "Kotiba application"
  putStrLn "Application ready to start"

  cn <- loadConfig op.cfg
  case cn of
    Success _ c -> do
      pool <- runStdoutLoggingT $ createPostgresqlPool (encodeUtf8 c.database) c.databasePoolSize
      manager <- newTlsManager
      baseUrl <- parseBaseUrl $ T.unpack c.forgejoUrl
      fgToken <- liftIO . fmap T.strip . TIO.readFile $ T.unpack c.forgejoToken
      let cenv = mkClientEnv manager baseUrl
          fc = c{forgejoToken = fgToken}
          st = MkAppSt{config = fc, db = pool, forgejo = mkAppEnv cenv ("token " <> fgToken)}
          settings = setPort c.port $ setHost "*" defaultSettings
      migrate' st
      seedIfChanged st c.seedFile
      let ?st = st
      runSettings settings (catchExceptions runApi)
    Failure _ -> putStrLn "Failed to load config"
