{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module API where

import API.Util (errorFormatters)
import Forgejo
import Kotiba.Prelude
import Servant
import Servant.Server.Generic

type API :: Type -> Type
data API route = MkAPI
  { health :: route :- "health" :> Get '[JSON] Integer
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
onPullRequest pl = do
  let org = pl.prpRepository.repoOwner.userLogin
  members <- withForgejo (getOrgMember org)
  liftIO $ print (userLogin <$> members)

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
    , webhook = webhookHandler handleWebhook
    }

heal :: Handler Integer
heal =
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
