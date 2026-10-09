{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OrPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module API where

import API.Dev (DevRoutes, devHandlers)
import API.Util (errorFormatters)
import Control.Monad (void)
import Events.Backport (processBackport)
import Events.PullRequest (processPrOpen)
import Events.Tracking.Job (TrackJob (..))
import Events.Tracking.Worker (enqueue)
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

{- | This function handles payload of webhook.
Pull request events are put in tracking queue first, after that they go to 'onPullRequest' as before.
-}
handleWebhook :: (AppState) => Delivery -> WebhookPayload -> Handler ()
handleWebhook d (WPPullRequest p) = do
  track d p
  onPullRequest p
handleWebhook _ (WPPush p) = onPush p
handleWebhook _ (WPIssueComment p) = onIssueComment p
handleWebhook _ (WPActionRun p) = onActionRun p
handleWebhook _ (WPRelease _) = pure ()

{- | This function puts pull request event in the queue of tracking worker.
Delivery id is the key of event, so request without it gets 400.
-}
track :: (AppState) => Delivery -> PullRequestPayload -> Handler ()
track d p = do
  delivery <- pure d.deliveryId !? err400{errBody = "missing X-Forgejo-Delivery header"}
  enqueue $ TrackJob delivery p

onPullRequest :: (AppState) => PullRequestPayload -> Handler ()
onPullRequest = \case
  pl@PullRequestPayload{prpAction = PrOpened} -> void $ processPrOpen pl
  pl@PullRequestPayload{prpAction = (PrClosed; PrLabelUpdated)} -> processBackport pl
  _ -> pure ()

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
    , webhook = webhookHandlerWith handleWebhook
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
