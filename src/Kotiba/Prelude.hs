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
  , OrgState
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

{- | Everything about one org, loaded at startup.
No 'Show' on purpose, so the token and secret can't end up in logs.
-}
data OrgEnv = OrgEnv
  { orgName :: Text
  -- ^ lowercased, same as the key in 'orgEnvs'
  , orgBot :: BotConfig
  , orgToken :: Text
  -- ^ used for git push/clone
  , orgWebhookSecret :: ByteString
  , orgForgejo :: AppEnv
  -- ^ client that uses 'orgToken'
  }

data AppSt = MkAppSt
  { config :: CanonicalConfig
  , db :: PoolSql
  , trackQueue :: TQueue TrackJob
  , orgEnvs :: Map Text OrgEnv
  -- ^ keys are lowercased
  }

lookupOrg :: (AppState) => Text -> Maybe OrgEnv
lookupOrg o = Map.lookup (toLower o) ?st.orgEnvs

type AppState :: Constraint
type AppState = (?st :: AppSt)

{- | The org of the current request or job. Needed only by things that talk to Forgejo.
Bind it in 'onWebhook' and in the worker, nowhere else.
Never at startup, or every org would act as that one.
-}
type OrgState :: Constraint
type OrgState = (?org :: OrgEnv)

-- | Runs as the bot of the current org. Errors turn into HTTP errors.
withForgejo :: (OrgState) => AppM a -> Handler a
withForgejo = runAppM ?org.orgForgejo

-- | Same, but you get the error back and handle it yourself.
tryForgejo :: (MonadIO m, OrgState) => AppM a -> m (Either ForgejoError a)
tryForgejo action = liftIO $ runForgejo ?org.orgForgejo action

withPool :: (MonadIO m, MonadReader AppSt m) => SqlPersistT IO a -> m a
withPool q = do
  pool <- asks (.db)
  liftIO $ runSqlPool q pool

migrate' :: AppSt -> IO ()
migrate' st = flip runReaderT st $ withPool (runMigration migrateAll)

infixl 0 !?

-- | Throw if 'Nothing'.
(!?) :: (MonadError e m) => m (Maybe a) -> e -> m a
action !? err = action >>= maybe (throwError err) pure

infixl 0 <??>

-- | Throw if 'Left', converting the error.
(<??>) :: (MonadError e m) => m (Either err a) -> (err -> e) -> m a
action <??> f = action >>= either (throwError . f) pure

infixl 0 !??

-- | '!?' for 'IO'.
(!??) :: (MonadError e m, MonadIO m) => IO (Maybe a) -> e -> m a
action !?? err = liftIO action >>= maybe (throwError err) pure

infixl 0 <!!>

-- | '<??>' for 'IO'.
(<!!>) :: (MonadError e m, MonadIO m) => IO (Either err a) -> (err -> e) -> m a
action <!!> f = liftIO action >>= either (throwError . f) pure
