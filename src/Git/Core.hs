{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RequiredTypeArguments #-}
{-# LANGUAGE TypeOperators #-}

module Git.Core
  ( GitError (..)
  , GitMonad
  , GitOperation (..)
  , GitOp (..)
  , withGit
  , requireGit
  , bestEffortGit
  , authHeaderArgs
  , repoPath
  , ensureClone
  , parentCount
  , setGitIdentity
  ) where

import Control.Monad (void)
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as T
import Kotiba.Prelude
import Named
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.FilePath (takeDirectory, (</>))
import System.Process.Typed

{- | Real, unrecoverable git failures. Any operation using these
means the current git workflow (backport, future clone-based
feature, etc.) cannot proceed
-}
data GitError
  = CloneFailed Text
  | FetchFailed Text
  | CheckoutFailed Text
  | ParentCountFailed Text
  | PushFailed Text
  | ConfigFailed Text
  deriving stock (Show)

type GitMonad m = (MonadIO m, MonadError GitError m)

{- | The set of git operations that can fail, used to tag `requireGit`
calls so the correct error constructor is inferred automatically.
-}
data GitOp = Clone | Fetch | Push | Checkout | ParentInspect | SetIdentity

-- | This typeclass defines default constraints for Git operations
type GitOperation :: GitOp -> Constraint
class GitOperation op where
  operationError :: Text -> GitError

instance GitOperation 'Clone where operationError = CloneFailed
instance GitOperation 'Fetch where operationError = FetchFailed
instance GitOperation 'Push where operationError = PushFailed
instance GitOperation 'Checkout where operationError = CheckoutFailed
instance GitOperation 'ParentInspect where operationError = ParentCountFailed
instance GitOperation 'SetIdentity where operationError = ConfigFailed

{- | Run git, returning captured stdout+stderr either way, so failures
carry real diagnostic content instead of an opaque error.
-}
withGit :: (MonadIO m) => FilePath -> [String] -> m (Either Text BL.ByteString)
withGit dir args = do
  (ec, out, err) <-
    readProcess
      $ setEnv [("GIT_TERMINAL_PROMPT", "0")]
      $ setWorkingDir dir
      $ proc "git" args
  pure $ case ec of
    ExitSuccess -> Right out
    ExitFailure _ -> Left $ T.pack . BL8.unpack $ out <> err

{- | Run git, throwing the operation's own GitError on failure.
Usage: requireGit (type Push) path args
-}
requireGit
  :: forall op
    ->(GitMonad m, GitOperation op)
  => FilePath
  -> [String]
  -> m BL.ByteString
requireGit op dir args = withGit dir args >>= either (throwError . operationError @op) pure

{- | Run git and discard the result either way. Use for best-effort,
expected-to-sometimes-fail steps (e.g. deleting a branch that may
not exist).
-}
bestEffortGit :: (MonadIO m) => FilePath -> [String] -> m ()
bestEffortGit dir args = void $ withGit dir args

{- | Config flags that inject a Forgejo API token as an HTTP Authorization
header into a single git invocation. Prepend to any git args that hit
the network (clone, fetch, push).
-}
authHeaderArgs :: Text -> [String]
authHeaderArgs token =
  [ "-c"
  , "http.extraHeader=Authorization: token " <> T.unpack token
  , "-c"
  , "http.followRedirects=false"
  ]

{- | This function is used to determine local repo path.
It takes dataDir, owner and repo argument.
-}
repoPath :: FilePath -> Text -> Text -> FilePath
repoPath dataDir owner repo = dataDir </> T.unpack owner </> T.unpack repo

{- | Ensure a local clone exists at dataDir/owner/repo, cloning fresh
or fetching if it already exists. Reusable by any feature that
needs a working tree, not just backporting.
-}
ensureClone
  :: (GitMonad m)
  => "dataDir" :! FilePath
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "token" :! Text
  -> m FilePath
ensureClone (Arg dataDir) (Arg owner) (Arg repo) (Arg cloneUrl) (Arg token) = do
  let path = repoPath dataDir owner repo
      headerArgs = authHeaderArgs token
  exists <- liftIO $ doesDirectoryExist path
  if exists
    then void $ requireGit (type Fetch) path ["fetch", "origin"]
    else do
      liftIO $ createDirectoryIfMissing True $ takeDirectory path
      void
        $ requireGit
          (type Clone)
          (takeDirectory path)
          (headerArgs <> ["clone", T.unpack cloneUrl, path])
  pure path

{- | Number of parents of a commit. 1 = normal commit, 2+ = merge commit.
Useful anywhere a commit's shape needs inspecting, not just cherry-pick.
-}
parentCount :: (GitMonad m) => FilePath -> Text -> m Int
parentCount path sha = do
  out <- requireGit (type ParentInspect) path ["rev-list", "--parents", "-n", "1", T.unpack sha]
  pure $ length (words $ BL8.unpack out) - 1

{- | Setting local Git identity for repo with 3 arguments:
path - repo path where should be setted identity
name - name of identity
email - email of identity
-}
setGitIdentity :: (GitMonad m) => FilePath -> Text -> Text -> m ()
setGitIdentity path name email = do
  void $ requireGit (type SetIdentity) path ["config", "user.name", T.unpack name]
  void $ requireGit (type SetIdentity) path ["config", "user.email", T.unpack email]
