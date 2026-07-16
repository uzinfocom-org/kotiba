module Forgejo.AppM where

import Control.Monad.Except (MonadError, throwError)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT (..), asks, runReaderT)
import Data.Text (Text)
import Forgejo.Client (ForgejoRoutes, forgejoRoutes)
import Servant (Handler, ServerError, err500, errBody)
import Servant.Client (AsClientT, ClientEnv, ClientM, runClientM)

data AppEnv = AppEnv
  { envClientEnv :: ClientEnv
  , envToken :: Text
  }

newtype AppM a = AppM {unAppM :: ReaderT AppEnv Handler a}
  deriving newtype (Applicative, Functor, Monad, MonadError ServerError, MonadIO, MonadReader AppEnv)

mkAppEnv :: ClientEnv -> Text -> AppEnv
mkAppEnv clientEnv token = AppEnv{envClientEnv = clientEnv, envToken = token}

runAppM :: AppEnv -> AppM a -> Handler a
runAppM env = flip runReaderT env . unAppM

liftClientM :: ClientM a -> AppM a
liftClientM action = do
  cenv <- asks envClientEnv
  liftIO (runClientM action cenv) >>= either handleError pure
 where
  handleError _err = throwError err500{errBody = mempty}

runForgejo :: (ForgejoRoutes (AsClientT ClientM) -> ClientM a) -> AppM a
runForgejo f = asks envToken >>= liftClientM . f . forgejoRoutes
