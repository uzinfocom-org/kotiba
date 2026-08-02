{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module API where

import API.Dev (DevRoutes, devHandlers)
import API.Util (errorFormatters)
import Control.Monad (void)
import Events.PullRequest (processPrOpen)
import Forgejo hiding (User, userId)
import Kotiba.Prelude
import Servant
import Servant.Server.Generic

type API :: Type -> Type
data API route = MkAPI
  { health :: route :- "health" :> Get '[JSON] Integer
  , dev :: route :- "dev" :> NamedRoutes DevRoutes
  , webhook :: route :- WebhookAPI
  }
  deriving stock (Generic)

handleWebhook :: (AppState) => WebhookPayload -> Handler ()
handleWebhook payload = case payload of
  WPPush p -> onPush p
  WPPullRequest p -> onPullRequest p
  WPIssueComment p -> onIssueComment p
  WPActionRun p -> onActionRun p

onPullRequest :: (AppState) => PullRequestPayload -> Handler ()
onPullRequest pl = void $ processPrOpen pl

onIssueComment :: (AppState) => IssueCommentPayload -> Handler ()
onIssueComment _ = pure ()

onPush :: (AppState) => PushPayload -> Handler ()
onPush _ = pure ()

onActionRun :: (AppState) => ActionRunPayload -> Handler ()
onActionRun _ = pure ()

data ApiServer route = MkApiServer
  { api :: route :- NamedRoutes API
  }
  deriving (Generic)

apiProxy :: Proxy (ToServantApi API)
apiProxy = Proxy

apiHandlers :: (AppState) => API AsServer
apiHandlers =
  MkAPI
    { health = heal
    , dev = devHandlers
    , webhook = webhookHandler handleWebhook
    }

heal :: (AppState) => Handler Integer
heal = do
  return 1

mkServer :: (AppState) => ApiServer AsServer
mkServer =
  MkApiServer
    { api = apiHandlers
    }

runApi :: (AppState) => Application
runApi =
  serveWithContext
    (Proxy @(ToServantApi ApiServer))
    errorFormatters
    (toServant $ mkServer)
