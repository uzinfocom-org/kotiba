{-# LANGUAGE OrPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pure functions which map payloads of Forgejo into our records for PR tracking. There's no IO here.
module Events.Tracking where

import Data.Bool (bool)
import Data.Text (Text)
import Database (frUser)
import Database.Types
  ( FrId (..)
  , PREventKind (..)
  , PullRequestFileStatus (..)
  , PullRequestState (..)
  , RepositoryId
  , UserId
  )
import Database.Types qualified as DB
import Forgejo.Types.PullRequest
  ( HookPullRequestAction (..)
  , PRBranch (..)
  , PullRequest (..)
  , PullRequestPayload (..)
  , ReviewPayload (..)
  )
import Forgejo.Types.User (User (..))

{- | This function defines the kind of event by payload.
Merged PR comes as closed one, so 'prMerged' is checked. Kind of review is taken from the type of review.
-}
eventKind :: PullRequestPayload -> PREventKind
eventKind PullRequestPayload{prpAction = PrClosed, prpPullRequest = pr} = bool PRClosed PRMerged pr.prMerged
eventKind PullRequestPayload{prpAction = PrReviewed, prpReview = review} = reviewKind review
eventKind PullRequestPayload{..} = actionKind prpAction

-- | This function maps action of PR into kind of event. Actions which we don't need become 'PROther'.
actionKind :: HookPullRequestAction -> PREventKind
actionKind = \case
  PrOpened -> PROpened
  PrReOpened -> PRReopened
  PrClosed -> PRClosed
  PrSynchronized -> PRSynchronized
  PrEdited -> PREdited
  PrAssigned -> PRAssigned
  PrUnassigned -> PRUnassigned
  PrReviewRequested -> PRReviewRequested
  (PrLabelUpdated; PrLabelCleared) -> PRLabelChanged
  (PrMilestoned; PrDemilestoned) -> PRMilestoned
  _ -> PROther

{- | This function defines the kind of review by its type.
Approved and rejected are checked on real deliveries, anything else is counted as comment.
-}
reviewKind :: Maybe ReviewPayload -> PREventKind
reviewKind = maybe PROther $ byType . (.rvType)
 where
  byType "pull_request_review_approved" = PRReviewApproved
  byType "pull_request_review_rejected" = DB.PRReviewRejected
  byType _ = DB.PRReviewCommented

{- | This function defines the state of PR.
Merged PR is never just closed, and reopened one is open again.
-}
stateOf :: PullRequest -> PullRequestState
stateOf PullRequest{..}
  | prMerged = StateMerged
  | prState == "closed" = StateClosed
  | otherwise = StateOpen

-- | This function gives Forgejo id and login of user, they are the arguments of 'getOrCreateUser'.
person :: User -> (FrId, Text)
person User{..} = (frUser userId, userLogin)

{- | This function creates the row of PR from payload.
It takes keys of repository, author and merger, which worker gets from database before.
Fields go in the same order as in the entity, so keep it in mind when the entity is changed.
Marker of files is empty at the start.
-}
toPullRequest :: RepositoryId -> UserId -> Maybe UserId -> PullRequest -> DB.PullRequest
toPullRequest repoKey author mergedBy pr =
  DB.PullRequest
    repoKey
    pr.prNumber
    author
    pr.prTitle
    (stateOf pr)
    pr.prDraft
    pr.prBase.branchRef
    pr.prCreatedAt
    pr.prClosedAt
    pr.prMergedAt
    mergedBy
    pr.prUpdatedAt
    Nothing

-- | This function maps status of file from Forgejo into our type. Unknown status becomes 'FileOther'.
fileStatus :: Text -> PullRequestFileStatus
fileStatus = \case
  "added" -> FileAdded
  "changed" -> FileChanged
  "deleted" -> FileDeleted
  "renamed" -> DB.FileRenamed
  "copied" -> DB.FileCopied
  "unchanged" -> DB.FileUnchanged
  _ -> DB.FileOther
