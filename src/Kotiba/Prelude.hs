{-# LANGUAGE NoFieldSelectors #-}

module Kotiba.Prelude
  ( -- * Types
    Type
  , Constraint
  , Generic
  , Text
  , MonadIO (..)
  , MonadError (..)
  , ToJSON
  , FromJSON
  -- 3rd party tools
  , printer

    -- * Application
  , AppSt (..)
  , AppState
  , AppEnv
  , AppM
  , withForgejo
  , Config (..)
  , withPool
  , migrate'
  ) where

import Config (Config (..))
import Control.Monad.Error.Class (MonadError (..))
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Reader (MonadReader, ReaderT (..), asks, runReaderT)
import Data.Aeson (FromJSON, ToJSON)
import Data.Kind (Constraint, Type)
import Data.Text (Text)
import Database.Persist.Sql (SqlPersistT, runMigration, runSqlPool)
import Database.Types
import Forgejo.App (AppEnv, AppM, runAppM)
import GHC.Generics (Generic)
import Servant (Handler)
import Shower (printer)

data AppSt = MkAppSt
  { config :: Config
  , db :: PoolSql
  , forgejo :: AppEnv
  }

type AppState :: Constraint
type AppState = (?st :: AppSt)

withForgejo :: (AppState) => AppM a -> Handler a
withForgejo = runAppM ?st.forgejo

withPool :: (MonadIO m, MonadReader AppSt m) => SqlPersistT IO a -> m a
withPool q = do
  pool <- asks (.db)
  liftIO $ runSqlPool q pool

migrate' :: AppSt -> IO ()
migrate' st = flip runReaderT st $ withPool (runMigration migrateAll)
