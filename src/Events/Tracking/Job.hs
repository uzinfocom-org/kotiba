-- | Job for the tracking worker. Webhook handler creates it and puts it in the queue.
module Events.Tracking.Job where

import Data.Text (Text)
import Forgejo.Types.PullRequest (PullRequestPayload)

{- | This type is one pull request event which waits for the worker.
It keeps the payload and the delivery id which comes from @X-Forgejo-Delivery@ header.
-}
data TrackJob = TrackJob
  { jobDelivery :: !Text
  -- ^ Id of delivery, it's the unique key of the event in database.
  , jobPayload :: !PullRequestPayload
  -- ^ Payload which is sent by Forgejo.
  }
