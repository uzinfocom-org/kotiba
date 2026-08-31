{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OrPatterns #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module API where

import API.Dev (DevRoutes, devHandlers)
import API.Util (errorFormatters)
import Control.Monad (void)
import Events.Backport (processBackport)
import Events.PullRequest (processPrOpen)
import Events.Release (processRelease)
import Forgejo hiding (User, userId)
import Forgejo.Types.Release (HookReleaseAction (..), ReleasePayload (..))
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
handleWebhook = \case
  WPPush p -> onPush p
  WPPullRequest p -> onPullRequest p
  WPIssueComment p -> onIssueComment p
  WPActionRun p -> onActionRun p
  WPRelease p -> onRelease p

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

onRelease = \case
  pl@ReleasePayload{rpAction = RelPublished} -> processRelease pl
  _ -> pure ()

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
