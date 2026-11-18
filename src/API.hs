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
import Kotiba.Webhook (OrgSecrets (..), SignedBody, Verified (..), WebhookSecret (..))
import Servant
import Servant.Server.Generic

type API :: Type -> Type
data API route = MkAPI
  { health :: route :- "health" :> Get '[JSON] Integer
  , dev :: route :- "dev" :> NamedRoutes DevRoutes
  , webhook :: route :- WebhookAPI SignedBody
  }
  deriving stock (Generic)

{- | This function handles payload of webhook.
Pull request events are put in tracking queue first, after that they go to 'onPullRequest' as before.
-}
handleWebhook :: (AppState) => OrgEnv -> Delivery -> WebhookPayload -> Handler ()
handleWebhook env d (WPPullRequest p) = do
  track env d p
  onPullRequest env p
handleWebhook _ _ (WPPush p) = onPush p
handleWebhook _ _ (WPIssueComment p) = onIssueComment p
handleWebhook _ _ (WPActionRun p) = onActionRun p
handleWebhook _ _ (WPRelease _) = pure ()

receiveWebhook
  :: (AppState)
  => Maybe (Either Text ForgejoEvent)
  -> Maybe (Either Text ForgejoEventType)
  -> Maybe Text
  -> Verified
  -> Handler ()
receiveWebhook ev evTy did (Verified org v) = do
  env <- pure (lookupOrg org) !? err401
  webhookHandlerWith (handleWebhook env) ev evTy did v

{- | This function puts pull request event in the queue of tracking worker.
Delivery id is the key of event, so request without it gets 400.
-}
track :: (AppState) => OrgEnv -> Delivery -> PullRequestPayload -> Handler ()
track env d p = do
  delivery <- pure d.deliveryId !? err400{errBody = "missing X-Forgejo-Delivery header"}
  enqueue $ TrackJob delivery env.orgName p

onPullRequest :: (AppState) => OrgEnv -> PullRequestPayload -> Handler ()
onPullRequest env = \case
  pl@PullRequestPayload{prpAction = PrOpened} -> void $ processPrOpen env pl
  pl@PullRequestPayload{prpAction = (PrClosed; PrLabelUpdated)} -> processBackport env pl
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
    , webhook = receiveWebhook
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
    (orgSecrets :. errorFormatters)
    (toServant mkServer)
 where
  orgSecrets :: OrgSecrets
  orgSecrets = OrgSecrets (fmap (Signed . (.orgWebhookSecret)) . lookupOrg)
