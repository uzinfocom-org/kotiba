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
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as T
import Kotiba.Prelude
import Named
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.Environment (getEnvironment)
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
  | CherryPickFailed Text
  deriving stock (Show)

data GitEnv = GitEnv
  { geToken :: Text
  , geEnv :: [(String, String)]
  }

mkGitEnv :: (MonadIO m) => Text -> m GitEnv
mkGitEnv token = do
  base <- liftIO getEnvironment
  pure
    GitEnv
      { geToken = token
      , geEnv = ("GIT_TERMINAL_PROMPT", "0") : filter ((/= "GIT_TERMINAL_PROMPT") . fst) base
      }

type GitMonad m = (MonadIO m, MonadError GitError m, MonadReader GitEnv m)

type GitM = ReaderT GitEnv (ExceptT GitError IO)

runGitM :: (MonadIO m) => GitEnv -> GitM a -> m (Either GitError a)
runGitM env action = liftIO . runExceptT $ runReaderT action env

{- | The set of git operations that can fail, used to tag `requireGit`
calls so the correct error constructor is inferred automatically.
-}
data GitOp = Clone | Fetch | Push | Checkout | ParentInspect | SetIdentity | CherryPick

-- | This typeclass defines default constraints for Git operations
type GitOperation :: GitOp -> Constraint
class GitOperation op where
  operationError :: Text -> GitError

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

gitArgs :: forall op. (GitOperation op) => GitEnv -> [String] -> [String]
gitArgs env args
  | needsAuth @op = authHeaderArgs env.geToken <> args
  | otherwise = args

runGit :: (MonadIO m) => GitEnv -> FilePath -> [String] -> m (Either Text BL.ByteString)
runGit env dir args = do
  (ec, out, err) <-
    readProcess
      $ setEnv env.geEnv
      $ setWorkingDir dir
      $ proc "git" args
  pure $ case ec of
    ExitSuccess -> Right out
    ExitFailure _ -> Left $ T.pack . BL8.unpack $ out <> err

requireGit
  :: forall op
  ->(GitMonad m, GitOperation op)
  => FilePath
  -> [String]
  -> m BL.ByteString
requireGit op dir args = do
  env <- ask
  runGit env dir (gitArgs @op env args) >>= either (throwError . operationError @op) pure

tryGit
  :: forall op
  ->(GitOperation op, MonadIO m, MonadReader GitEnv m)
  => FilePath
  -> [String]
  -> m (Either Text BL.ByteString)
tryGit op dir args = do
  env <- ask
  runGit env dir (gitArgs @op env args)

bestEffortGit :: (MonadIO m, MonadReader GitEnv m) => FilePath -> [String] -> m ()
bestEffortGit dir args = do
  env <- ask
  void $ runGit env dir args
