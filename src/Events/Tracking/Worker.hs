{-# LANGUAGE OrPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Worker which saves pull request deliveries into database. Webhook handler only puts jobs in the queue, this module does the rest.
module Events.Tracking.Worker
  ( TrackError (..)
  , renderTrackError
  , enqueue
  , worker
  ) where

import Control.Concurrent.STM (atomically, readTQueue, writeTQueue)
import Control.Exception.Safe (tryAny)
import Control.Monad (forM, forever, unless, when)
import Control.Monad.Except (ExceptT, liftEither, runExceptT)
import Control.Monad.Logger (logErrorN, runStdoutLoggingT)
import Data.Text qualified as T
import Database
import Database.Persist ((=.))
import Database.PullRequest
import Database.Types hiding (PullRequestCommit, Repository, User)
import Database.Types qualified as DB
import Events.Tracking
import Events.Tracking.Job (TrackJob (..))
import Forgejo.Error (ForgejoError)
import Forgejo.Methods.PullRequest (getPullRequestCommits, getPullRequestFiles)
import Forgejo.Types.ChangedFile (ChangedFile (..))
import Forgejo.Types.PullRequest (PullRequest (..), PullRequestPayload (..))
import Forgejo.Types.PullRequestCommit (PullRequestCommit (..), isMergeCommit)
import Forgejo.Types.Repository (Repository (..))
import Forgejo.Types.User (User (..))
import Kotiba.Prelude

{- | Errors of tracking.
'TrackCrashed' keeps the exception from database layer, which 'safely' turns into value.
-}
data TrackError
  = TrackForgejo ForgejoError
  | TrackCrashed Text
  deriving stock (Show)

-- | This function renders error as text, it's saved in 'failure' of the event.
renderTrackError :: TrackError -> Text
renderTrackError = T.pack . show

-- | This function puts the job in the queue. It never blocks, because the queue is unbounded.
enqueue :: (AppState, MonadIO m) => TrackJob -> m ()
enqueue = liftIO . atomically . writeTQueue ?st.trackQueue

{- | This is the main loop of the module.
It takes jobs one by one, so events of the same PR go in order. Failed job doesn't stop the loop.
-}
worker :: (AppState) => IO ()
worker = forever $ do
  job <- atomically $ readTQueue ?st.trackQueue
  runExceptT (runJob job) >>= either (lastResort job) pure

{- | This function logs errors which can't be saved on the event:
there's no event yet, or the database itself is failing.
-}
lastResort :: TrackJob -> TrackError -> IO ()
lastResort job e =
  runStdoutLoggingT . logErrorN $ "Tracking " <> job.jobDelivery <> " failed: " <> renderTrackError e

{- | This function runs one job. It skips finished delivery, records the event,
fetches files and commits if needed and saves how the job ended.
-}
runJob :: (AppState) => TrackJob -> ExceptT TrackError IO ()
runJob job = do
  done <- safely $ isEventDone job.jobDelivery
  unless done $ do
    (prKey, evKey) <- safely $ record job
    outcome <- liftIO . runExceptT . safely $ enrich job prKey
    safely $ finish evKey outcome

-- | This function saves the result of job on the event: done, or failed with reason.
finish :: (AppState) => PullRequestEventId -> Either TrackError () -> ExceptT TrackError IO ()
finish evKey =
  either (failEvent evKey . renderTrackError) (const $ setEventStatus evKey EventDone)

{- | This function saves everything which doesn't need Forgejo API: repository, people, PR and event.
It returns keys of PR and event.
-}
record :: (AppState) => TrackJob -> ExceptT TrackError IO (PullRequestId, PullRequestEventId)
record job = do
  let payload = job.jobPayload
      pr = payload.prpPullRequest
      repoId = frRepo payload.prpRepository.repoId
      url = payload.prpRepository.repoCloneUrl
      name = payload.prpRepository.repoName
      repo = DB.Repository repoId url name

  repoKey <- upsertBy
    (UniqueRepositoryFrRepoId repoId)
    [RepositoryFrRepoId =. repoId]
    repo

  authorKey <- resolveUser pr.prUser
  mergedByKey <- traverse resolveUser pr.prMergedBy
  actorKey <- resolveUser payload.prpSender
  prKey <- upsertPullRequest $ toPullRequest repoKey authorKey mergedByKey pr
  evKey <- startEvent job.jobDelivery prKey (eventKind payload) actorKey pr.prUpdatedAt
  pure (prKey, evKey)

{- | This function fetches files and commits of PR and replaces them in database.
It's done when the event changes content of PR, or when PR was never fetched before.
Marker is set at the end, so failed fetch is retried by the next event.
-}
enrich :: (AppState) => TrackJob -> PullRequestId -> ExceptT TrackError IO ()
enrich job prKey = do
  synced <- filesSynced prKey
  when (needsFiles (eventKind payload) || not synced) $ do
    files <- tryForgejo (getPullRequestFiles owner repo number Nothing) <??> TrackForgejo
    commits <- tryForgejo (getPullRequestCommits owner repo number Nothing) <??> TrackForgejo
    commitRows <- forM commits $ \c -> do
      author <- traverse (uncurry getOrCreateUser) $ commitPerson c
      pure $ toCommit prKey author c
    replaceFiles prKey $ toFile prKey <$> files
    replaceCommits prKey commitRows
    markFilesSynced prKey
  where
  payload = job.jobPayload
  owner = payload.prpRepository.repoOwner.userLogin
  repo = payload.prpRepository.repoName
  number = payload.prpPullRequest.prNumber

-- | This function creates the row of changed file. It's not removed yet, so 'removedAt' is Nothing.
toFile :: PullRequestId -> ChangedFile -> PullRequestFile
toFile pr f = PullRequestFile pr f.filename (fileStatus f.status) Nothing

{- | This function tells if the event changes content of PR (opened, reopened, synchronized).
Only for such events we fetch files and commits from Forgejo.
-}
needsFiles :: PREventKind -> Bool
needsFiles (PROpened; PRReopened; PRSynchronized) = True
needsFiles _ = False

{- | This function gives Forgejo id and login of author of commit.
If git email is not linked to any user in Forgejo, it returns Nothing.
-}
commitPerson :: PullRequestCommit -> Maybe (FrId, Text)
commitPerson = fmap person . (.pcAuthorUser)

{- | This function creates the row of commit. Author is Nothing when git email is not linked to user,
in that case git name of author stays in 'authorName'.
-}
toCommit :: PullRequestId -> Maybe UserId -> PullRequestCommit -> DB.PullRequestCommit
toCommit pr author c =
  DB.PullRequestCommit
    pr
    c.pcSha1
    author
    c.pcAuthorName
    c.pcAuthoredAt
    $ isMergeCommit c

-- | This function gets user from database by Forgejo account, unknown one is created without role.
resolveUser :: (AppState, MonadIO m) => User -> m DB.UserId
resolveUser = uncurry getOrCreateUser . person

{- | This function turns exception from database layer into 'TrackCrashed'.
It's the only place where exceptions are caught.
-}
safely :: ExceptT TrackError IO a -> ExceptT TrackError IO a
safely step = do
  outcome <- liftIO . tryAny $ runExceptT step
  either (throwError . TrackCrashed . T.pack . show) liftEither outcome
