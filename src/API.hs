{-# LANGUAGE OrPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

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
import Kotiba.Webhook (OrgLookup (..), SignedBody, onWebhook)
import Servant
import Servant.Server.Generic

type API :: Type -> Type
data API route = MkAPI
  { health :: route :- "health" :> Get '[JSON] Integer
  , dev :: route :- "dev" :> NamedRoutes DevRoutes
  , webhook :: route :- WebhookAPI SignedBody
  }
  deriving stock (Generic)

handleWebhook :: (AppState, OrgState) => Delivery -> WebhookPayload -> Handler ()
handleWebhook d (WPPullRequest p) = do
  track d p
  onPullRequest p
handleWebhook _ (WPPush p) = onPush p
handleWebhook _ (WPIssueComment p) = onIssueComment p
handleWebhook _ (WPActionRun p) = onActionRun p
handleWebhook _ (WPRelease _) = pure ()

track :: (AppState, OrgState) => Delivery -> PullRequestPayload -> Handler ()
track d p = do
  delivery <- pure d.deliveryId !? err400{errBody = "missing X-Forgejo-Delivery header"}
  enqueue $ TrackJob delivery ?org.orgName p

onPullRequest :: (AppState, OrgState) => PullRequestPayload -> Handler ()
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

newtype ApiServer route = MkApiServer
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
    , webhook = onWebhook handleWebhook
    }

heal :: (AppState) => Handler Integer
heal = do
  return 1

mkServer :: (AppState) => ApiServer AsServer
mkServer =
  MkApiServer
    { api = apiHandlers
    }

-- | 'OrgLookup' in the context is what 'SignedBody' uses to find the org.
runApi :: (AppState) => Application
runApi =
  serveWithContext
    (Proxy @(ToServantApi ApiServer))
    (OrgLookup lookupOrg :. errorFormatters)
    (toServant mkServer)
