{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RequiredTypeArguments #-}

module Git.Core
  ( GitError (..)
  , GitEnv
  , GitM
  , GitMonad
  , GitOperation
  , GitOp (..)
  , mkGitEnv
  , runGitM
  , requireGit
  , tryGit
  , bestEffortGit
  ) where

import Control.Monad (void)
import Control.Monad.Except (ExceptT, runExceptT)
import Control.Monad.Reader (MonadReader, ReaderT, asks, runReaderT)
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as T
import Kotiba.Prelude
import System.Environment (getEnvironment)
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
  | CherryPickFailed Text
  deriving stock (Show)

{- | Everything git subprocesses need from outside.
It's created once by 'mkGitEnv' and passed around through 'MonadReader'
-}
data GitEnv = GitEnv
  { geToken :: Text
  -- ^ Forgejo token itself
  , geEnv :: [(String, String)]
  -- ^ Environment of git subprocess
  }

{- | This function creates 'GitEnv' from Fogrejo token.
It inherits current process and adds @GIT_TERMINAL_PROMPT@, so it fails instead of asking for credentials interactively
-}
mkGitEnv :: (MonadIO m) => Text -> m GitEnv
mkGitEnv token = do
  base <- liftIO getEnvironment
  pure
    GitEnv
      { geToken = token
      , geEnv = ("GIT_TERMINAL_PROMPT", "0") : filter ((/= "GIT_TERMINAL_PROMPT") . fst) base
      }

-- | Contraints rqeuired by git operations: 'IO', 'GitError' for failures and 'GitEnv' for auth.
type GitMonad m = (MonadIO m, MonadError GitError m, MonadReader GitEnv m)

-- | Concrete stack which satisfies 'GitMonad'. It's executed by 'runGitM'
type GitM = ReaderT GitEnv (ExceptT GitError IO)

-- | This function runs 'GitM' action with given 'GitEnv' and returns 'GitError' as 'Either'
runGitM :: (MonadIO m) => GitEnv -> GitM a -> m (Either GitError a)
runGitM env action = liftIO . runExceptT $ runReaderT action env

{- | The set of git operations that can fail, used to tag `requireGit`
calls so the correct error constructor is inferred automatically.
-}
data GitOp = Clone | Fetch | Push | Checkout | ParentInspect | SetIdentity | CherryPick

-- | This typeclass defines properties of every 'GitOp'
type GitOperation :: GitOp -> Constraint
class GitOperation op where
  -- | Constructor of 'GitError' which is used when operation fails
  operationError :: Text -> GitError

  {- | Whether operation talks to remote.
  If it does, 'gitArgs' adds auth header automatically. Default to 'False'.
  -}
  needsAuth :: Bool
  needsAuth = False

instance GitOperation 'Clone where
  operationError = CloneFailed
  needsAuth = True

instance GitOperation 'Fetch where
  operationError = FetchFailed
  needsAuth = True
instance GitOperation 'Push where
  operationError = PushFailed
  needsAuth = True

instance GitOperation 'Checkout where operationError = CheckoutFailed
instance GitOperation 'ParentInspect where operationError = ParentCountFailed
instance GitOperation 'SetIdentity where operationError = ConfigFailed
instance GitOperation 'CherryPick where operationError = CherryPickFailed

{- | Config flags that inject a Forgejo API token as an HTTP Authorization
header into a single git invocation.
It's internal, callers don't use it directly: 'gitArgs' adds it for every operation with 'needsAuth'
-}
authHeaderArgs :: Text -> [String]
authHeaderArgs token =
  [ "-c"
  , "http.extraHeader=Authorization: token " <> T.unpack token
  , "-c"
  , "http.followRedirects=false"
  ]

-- | This function prepends 'authHeadersArgs' to git arguments if operation 'needsAuth'
gitArgs :: forall op m. (GitOperation op, MonadReader GitEnv m) => [String] -> m [String]
gitArgs args
  | needsAuth @op = asks (\env -> authHeaderArgs env.geToken <> args)
  | otherwise = pure args

{- | Run git with environment from 'GitEnv'. On success returns stdout, on failure
returns stdout followed by stderr, so failures carry real diagnostic content
instead of an opaque error.
-}
runGit :: (MonadIO m, MonadReader GitEnv m) => FilePath -> [String] -> m (Either Text BL.ByteString)
runGit dir args = do
  genv <- asks (.geEnv)
  (ec, out, err) <-
    readProcess
      $ setEnv genv
      $ setWorkingDir dir
      $ proc "git" args
  pure $ case ec of
    ExitSuccess -> Right out
    ExitFailure _ -> Left $ T.pack . BL8.unpack $ out <> err

{- | Run git, throwing the operation's own 'GitError' on failure.
Usage: requireGit (type Push) path args
-}
requireGit
  :: forall op
  ->(GitMonad m, GitOperation op)
  => FilePath
  -> [String]
  -> m BL.ByteString
requireGit op dir args =
  tryGit op dir args >>= either (throwError . operationError @op) pure

{- | Same as 'requireGit', but returns failure output instead of throwing.
Use it where failure is an expected result (e.g. conflict while cherry-picking).
-}
tryGit
  :: forall op
  ->(GitOperation op, MonadIO m, MonadReader GitEnv m)
  => FilePath
  -> [String]
  -> m (Either Text BL.ByteString)
tryGit op dir args = gitArgs @op args >>= runGit dir

{- | Run local git command and discard the result either way. Use for best-effort,
expected-to-sometimes-fail steps (e.g. deleting a branch that may not exist).
It never injects auth, so don't use it for network operations.
-}
bestEffortGit :: (MonadIO m, MonadReader GitEnv m) => FilePath -> [String] -> m ()
bestEffortGit dir args = void $ runGit dir args
