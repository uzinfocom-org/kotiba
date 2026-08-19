{-# LANGUAGE MultilineStrings #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Events.Backport where

import Control.Monad (forM_, unless, void, when)
import Data.Int (Int64)
import Data.Maybe (mapMaybe)
import Data.Text qualified as T
import Database qualified as DB
import Database.Types (BackportStatus (..))
import Forgejo.Error (ForgejoError (..))
import Forgejo.Methods.Issue (createIssueComment)
import Forgejo.Methods.PullRequest (createPullRequest)
import Forgejo.Types.Common (RepoId (..))
import Forgejo.Types.CreateIssueCommentOption (CreateIssueCommentApiOption (..), CreateIssueCommentOption (..))
import Forgejo.Types.CreatePullRequestOption (CreatePullRequestOption (..))
import Forgejo.Types.Label (Label (..))
import Forgejo.Types.PullRequest (PullRequest (..), PullRequestPayload (..))
import Forgejo.Types.Repository (Repository (..))
import Forgejo.Types.User (User (..))
import Git.Backport (BackportResult (..), cherryPick)
import Git.Core (GitError (..))
import Kotiba.Prelude
import Named
import Servant (Handler)

-- | This function is used to define prefix of backport label.
backportPrefix :: Text
backportPrefix = "backport "

{- | This function extracts target branch from labels.
If there's no target branch, it returns Nothing.
__Example label__:
@
"backport release-26.05"
@
-}
parseBackportTarget :: Label -> Maybe Text
parseBackportTarget lbl = T.replace " " "-" <$> T.stripPrefix backportPrefix lbl.lName

{- | This function is used to extract target branch from merged PR
It extracts labels from 'PullRequest' and gives it to 'parseBackportTarget' in order to extract exact target branch
-}
backportTargets :: PullRequest -> [Text]
backportTargets pr = mapMaybe parseBackportTarget pr.prLabels

{- | This function creates overall argument for 'createPullRequest' method from 'Forgejo' library.
It takes pr, target and branch in order to create options.
-}
backportPullRequestOption :: PullRequest -> Text -> Text -> CreatePullRequestOption
backportPullRequestOption pr target branch =
  CreatePullRequestOption
    { cproHead = branch
    , cproBase = target
    , cproTitle = backportTitle pr target
    , cproBody = Just (backportBody pr target)
    , cproAssignee = Nothing
    , cproAssignees = []
    , cproDueDate = Nothing
    , cproLabels = []
    , cproMilestone = Nothing
    }

{- | This function creates title of backport PR.
It takes 'PullRequest' record and target arguments.
-}
backportTitle :: PullRequest -> Text -> Text
backportTitle pr target =
  "[Backport " <> target <> "] #" <> T.pack (show pr.prNumber) <> " " <> pr.prTitle

{- | This function creates body of backport PR.
It takes 'PullRequest' record and target arguments.
-}
backportBody :: PullRequest -> Text -> Text
backportBody pr target =
  """
  Automatic backport, triggered by a label on #"""
    <> T.pack (show pr.prNumber)
    <> """
       . Please confirm this is appropriate for """
    <> target
    <> " before merging."

-- | This function is used to render errors based on 'GitError' ADT in 'processBackport' function.
renderGitError :: GitError -> Text
renderGitError = \case
  CloneFailed t -> "Clone failed:\n" <> t
  FetchFailed t -> "Fetch failed:\n" <> t
  CheckoutFailed t -> "Checkout failed:\n" <> t
  ParentCountFailed t -> "Could not inspect commit:\n" <> t
  PushFailed t -> "Push failed:\n" <> t
  ConfigFailed t -> "Setting git identity is failed:\n" <> t

-- | Render a Forgejo API failure for use in a maintainer-facing comment.
renderForgejoError :: ForgejoError -> Text
renderForgejoError = \case
  ErrBadRequest msg _ -> "Forgejo rejected the request:\n" <> msg
  ErrUnauthorized msg _ -> "Authentication with Forgejo failed:\n" <> msg
  ErrForbidden msg _ -> "The bot lacks permission to do this:\n" <> msg
  ErrNotFound msg _ _ -> "Forgejo could not find the resource:\n" <> msg
  ErrConflict msg _ -> "Conflicting state on Forgejo (a backport PR may already exist):\n" <> msg
  ErrValidation msg _ -> "Forgejo rejected the request as invalid:\n" <> msg
  ErrInvalidTopics _ url -> "Forgejo rejected invalid topics, see:\n" <> url
  ErrRepoArchived msg _ -> "The repository is archived:\n" <> msg
  ErrServer msg _ -> "Forgejo had an internal error:\n" <> msg
  ErrDecodeFailure msg -> "Could not decode Forgejo's response:\n" <> msg
  ErrNetwork msg -> "Network error talking to Forgejo:\n" <> msg
  ErrUnexpected code msg -> "Unexpected response (" <> T.pack (show code) <> "):\n" <> msg

-- | This function creates line of mentioned usernames splitted by spaces from list of Texts.
mentionLine :: [Text] -> Text
mentionLine [] = ""
mentionLine users = T.intercalate " " (map ("@" <>) users) <> "\n\n"

{- | The purpose of this function is creating text of comment about failure.
It's used by 'commentOnFailure' function.
-}
backportFailureComment :: [Text] -> Text -> Text -> Text
backportFailureComment maintainers target diagnostic =
  mentionLine maintainers
    <> """
       Automatic backport to `"""
    <> target
    <> """
       ` could not be completed.
       """
    <> T.take 2000 diagnostic
    <> """

       Please resolve this manually on `"""
    <> target
    <> """
       `, or update the branch and re-add the `backport """
    <> target
    <> """
       ` label to retry.
       """

{- | This function is used to create comment about failure while backporting in source PR.
It uses 'createIssueComment' method and 'CreateIssueCommentOption' from 'Forgejo' library for commenting.
-}
commentOnFailure :: (AppState) => Text -> Text -> Int -> Int -> Text -> Text -> Handler ()
commentOnFailure owner repo prNumber repoFrId target diagnostic = do
  maintainers <- DB.getMaintainerUsernames repoFrId
  let body = backportFailureComment maintainers target diagnostic
      opts =
        CreateIssueCommentOption
          { ciscoOwner = owner
          , ciscoRepo = repo
          , ciscoIndex = prNumber
          , ciscoApiJson = CreateIssueCommentApiOption body
          }
  res <- tryForgejo $ createIssueComment opts
  case res of
    Right _ -> pure ()
    Left commentErr -> liftIO $ printer commentErr

{- | This is the main function of 'Events.Backport' module.
It calls to 'cherryPick' function from 'Git.Backport' module in order to operate local cherry-pick actions.
Based on results of 'cherryPick', this function writes records to its own DB and informs maintainers of repository in source PR if there's an error.
When it comes to successful results, 'processBackport' creates backport pull request to target branch which is indicated in label.
-}
processBackport :: (AppState) => PullRequestPayload -> Handler ()
processBackport PullRequestPayload{..} = do
  let pr = prpPullRequest
      owner = prpRepository.repoOwner.userLogin
      repo = prpRepository.repoName
      RepoId repoIdRaw = prpRepository.repoId
      repoFrId = fromIntegral @Int64 repoIdRaw
      cloneUrl = prpRepository.repoCloneUrl
  when pr.prMerged $ forM_ (backportTargets pr) $ \target -> do
    succeeded <- DB.backportSucceeded pr.prNumber repoFrId target
    unless succeeded $ case pr.prMergeCommitSha of
      Nothing -> pure ()
      Just sha -> do
        result <-
          liftIO
            $ cherryPick
              ! #dataDir ?st.config.dataDir
              ! #owner owner
              ! #repo repo
              ! #cloneUrl cloneUrl
              ! #token ?st.config.forgejoToken
              ! #srcNum pr.prNumber
              ! #target target
              ! #sha sha
        case result of
          Left gitErr -> do
            DB.recordBackport pr.prNumber repoFrId target Nothing BPError
            commentOnFailure owner repo pr.prNumber repoFrId target (renderGitError gitErr)
          Right (BackportConflict diagnostic) -> do
            DB.recordBackport pr.prNumber repoFrId target Nothing BPConflict
            commentOnFailure owner repo pr.prNumber repoFrId target diagnostic
          Right (BackportPushed _ branch) -> do
            let opts = backportPullRequestOption pr target branch
            prRes <- tryForgejo $ createPullRequest owner repo opts
            case prRes of
              Left fgErr -> do
                DB.recordBackport pr.prNumber repoFrId target Nothing BPError
                commentOnFailure owner repo pr.prNumber repoFrId target (renderForgejoError fgErr)
              Right newPr -> DB.recordBackport pr.prNumber repoFrId target (Just newPr.prNumber) BPOpened
