{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RequiredTypeArguments #-}

-- | Database operations related to pull requests.
module Database.PullRequest where

import Control.Monad (forM_)
import Data.Time (UTCTime, getCurrentTime)
import Database (deleteWhere, existsWhere, getBy, updateById, updateWhere, upsertBy)
import Database.Persist (Entity (..), (!=.), (=.), (/<-.), (==.))
import Database.Types
import Kotiba.Prelude

-- | Gets or creates user.
getOrCreateUser :: (AppState, MonadIO m) => FrId -> Text -> m UserId
getOrCreateUser frId login =
  upsertBy
    (UniqueUserFrId frId)
    [UserLogin =. login, UserUsername =. login]
    $ User login login frId Nothing

-- | This function is used to upsert pull request.
upsertPullRequest :: (AppState, MonadIO m) => PullRequest -> m PullRequestId
upsertPullRequest pr = do
  stored <- getBy (type (Entity PullRequest)) key
  case stored of
    Just (Entity existingId existingPr)
      | existingPr.pullRequestUpdatedAt > pr.pullRequestUpdatedAt ->
          pure existingId
    _ ->
      upsertBy
        key
        [ PullRequestTitle =. pr.pullRequestTitle
        , PullRequestState =. pr.pullRequestState
        , PullRequestDraft =. pr.pullRequestDraft
        , PullRequestBaseBranch =. pr.pullRequestBaseBranch
        , PullRequestClosedAt =. pr.pullRequestClosedAt
        , PullRequestMergedAt =. pr.pullRequestMergedAt
        , PullRequestMergedBy =. pr.pullRequestMergedBy
        , PullRequestUpdatedAt =. pr.pullRequestUpdatedAt
        ]
        pr
 where
  key = UniquePullRequest pr.pullRequestRepository pr.pullRequestNumber

-- | Checks if files are synced.
filesSynced :: (AppState, MonadIO m) => PullRequestId -> m Bool
filesSynced pr = existsWhere [PullRequestId ==. pr, PullRequestFilesSyncedAt !=. Nothing]

-- | Marks files as synced.
markFilesSynced :: (AppState, MonadIO m) => PullRequestId -> m ()
markFilesSynced pr = do
  now <- liftIO getCurrentTime
  updateById pr [PullRequestFilesSyncedAt =. Just now]

-- | Check if event is done.
isEventDone :: (AppState, MonadIO m) => Text -> m Bool
isEventDone delivery =
  existsWhere [PullRequestEventDeliveryId ==. delivery, PullRequestEventStatus ==. EventDone]

-- | Marks event as started.
startEvent :: (AppState, MonadIO m) => Text -> PullRequestId -> PREventKind -> UserId -> UTCTime -> m PullRequestEventId
startEvent delivery pr kind actor occurredAt = do
  now <- liftIO getCurrentTime
  upsertBy
    (UniquePullRequestEventDeliveryId delivery)
    [PullRequestEventStatus =. EventReceived, PullRequestEventFailure =. Nothing]
    $ PullRequestEvent delivery pr kind actor occurredAt now EventReceived Nothing

-- | Marks event as failed.
failEvent :: (AppState, MonadIO m) => PullRequestEventId -> Text -> m ()
failEvent k reason = updateById k [PullRequestEventStatus =. EventFailed, PullRequestEventFailure =. Just reason]

-- | Sets event status
setEventStatus :: (AppState, MonadIO m) => PullRequestEventId -> PREventStatus -> m ()
setEventStatus k s = updateById k [PullRequestEventStatus =. s]

-- | Replaces files by pull request id.
replaceFiles :: (AppState, MonadIO m) => PullRequestId -> [PullRequestFile] -> m ()
replaceFiles pr files = do
  now <- liftIO getCurrentTime
  let filenames = (.pullRequestFileFilename) <$> files
  updateWhere
    [ PullRequestFilePullRequest ==. pr
    , PullRequestFileFilename /<-. filenames
    , PullRequestFileRemovedAt ==. Nothing
    ]
    [PullRequestFileRemovedAt =. Just now]
  forM_ files $ \f ->
    upsertBy
      (UniquePullRequestFile pr f.pullRequestFileFilename)
      [PullRequestFileStatus =. f.pullRequestFileStatus]
      f

-- | Replaces commits by pull request id.
replaceCommits :: (AppState, MonadIO m) => PullRequestId -> [PullRequestCommit] -> m ()
replaceCommits pr commits = do
  let shas = (.pullRequestCommitSha) <$> commits
  deleteWhere [PullRequestCommitPullRequest ==. pr, PullRequestCommitSha /<-. shas]
  forM_ commits $ \c ->
    upsertBy
      (UniquePullRequestCommit pr c.pullRequestCommitSha)
      [ PullRequestCommitAuthor =. c.pullRequestCommitAuthor
      , PullRequestCommitAuthorName =. c.pullRequestCommitAuthorName
      , PullRequestCommitAuthoredAt =. c.pullRequestCommitAuthoredAt
      , PullRequestCommitIsMerge =. c.pullRequestCommitIsMerge
      ]
      c
