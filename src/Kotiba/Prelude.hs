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

    -- * Lifting operators
  , (!?)
  , (<??>)
  , (!??)
  , (<!!>)

    -- * Application
  , AppSt (..)
  , AppState
  , AppEnv
  , AppM
  , withForgejo
  , tryForgejo
  , Config (..)
  , CanonicalConfig
  , BotConfig (..)
  , OrgEnv (..)
  , lookupOrg
  , withPool
  , migrate'
  ) where

import Config (BotConfig (..), CanonicalConfig, Config (..))
import Control.Concurrent.STM (TQueue)
import Control.Monad.Error.Class (MonadError (..))
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Reader (MonadReader, ReaderT (..), asks, runReaderT)
import Data.Aeson (FromJSON, ToJSON)
import Data.ByteString (ByteString)
import Data.Kind (Constraint, Type)
import Data.Map (Map)
import Data.Map qualified as Map
import Data.Text (Text, toLower)
import Database.Persist.Sql (SqlPersistT, runMigration, runSqlPool)
import Database.Types
import Events.Tracking.Job (TrackJob)
import Forgejo.App (AppEnv, AppM, runAppM, runForgejo)
import Forgejo.Error (ForgejoError (..))
import GHC.Generics (Generic)
import Servant (Handler)
import Shower (printer)

data OrgEnv = OrgEnv
  { orgName :: Text
  , orgBot :: BotConfig
  , orgToken :: Text
  , orgWebhookSecret :: ByteString
  , orgForgejo :: AppEnv
  }

data AppSt = MkAppSt
  { config :: CanonicalConfig
  , db :: PoolSql
  , trackQueue :: TQueue TrackJob
  , orgEnvs :: Map Text OrgEnv
  }

lookupOrg :: (AppState) => Text -> Maybe OrgEnv
lookupOrg o = Map.lookup (toLower o) ?st.orgEnvs

type AppState :: Constraint
type AppState = (?st :: AppSt)

withForgejo :: OrgEnv -> AppM a -> Handler a
withForgejo org = runAppM org.orgForgejo

tryForgejo :: (MonadIO m) => OrgEnv -> AppM a -> m (Either ForgejoError a)
tryForgejo org = liftIO . runForgejo org.orgForgejo

withPool :: (MonadIO m, MonadReader AppSt m) => SqlPersistT IO a -> m a
withPool q = do
  pool <- asks (.db)
  liftIO $ runSqlPool q pool

migrate' :: AppSt -> IO ()
migrate' st = flip runReaderT st $ withPool (runMigration migrateAll)

infixl 0 !?

(!?) :: (MonadError e m) => m (Maybe a) -> e -> m a
action !? err = action >>= maybe (throwError err) pure

infixl 0 <??>

(<??>) :: (MonadError e m) => m (Either err a) -> (err -> e) -> m a
action <??> f = action >>= either (throwError . f) pure

infixl 0 !??

(!??) :: (MonadError e m, MonadIO m) => IO (Maybe a) -> e -> m a
action !?? err = liftIO action >>= maybe (throwError err) pure

infixl 0 <!!>

(<!!>) :: (MonadError e m, MonadIO m) => IO (Either err a) -> (err -> e) -> m a
action <!!> f = liftIO action >>= either (throwError . f) pure
