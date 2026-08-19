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
  , (<!!>)

    -- * Application
  , AppSt (..)
  , AppState
  , AppEnv
  , AppM
  , withForgejo
  , tryForgejo
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
import Forgejo.App (AppEnv, AppM, runAppM, runForgejo)
import Forgejo.Error (ForgejoError (..))
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

tryForgejo :: (AppState, MonadIO m) => AppM a -> m (Either ForgejoError a)
tryForgejo action = liftIO $ runForgejo ?st.forgejo action

withPool :: (MonadIO m, MonadReader AppSt m) => SqlPersistT IO a -> m a
withPool q = do
  pool <- asks (.db)
  liftIO $ runSqlPool q pool

migrate' :: AppSt -> IO ()
migrate' st = flip runReaderT st $ withPool (runMigration migrateAll)

infixl 0 <!!>

(<!!>) :: (MonadError e m, MonadIO m) => IO (Either err a) -> (err -> e) -> m a
action <!!> f = liftIO action >>= either (throwError . f) pure
