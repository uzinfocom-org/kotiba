{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Git.Backport
  ( BackportResult (..)
  , cherryPick
  ) where

import Control.Monad (void)
import Control.Monad.Except (ExceptT, runExceptT)
import Data.Text qualified as T
import Git.Core
import Kotiba.Prelude
import Named

-- | BackportResult is for defining overall result of backporting.
data BackportResult = BackportPushed FilePath Text | BackportConflict Text
  deriving stock (Eq, Show)

{- | This function requires 2 arguments for creating branch name quickly:
srcNum - PR number of repo
target - target branch name where should source PR should be backported
-}
backportBranchName :: Int -> Text -> String
backportBranchName srcNum target = "backport-" <> show srcNum <> "-to-" <> T.unpack target

{- | This function is separated in error handling purposes from 'cherryPick'.
It requires all arguments of 'cherryPick' function in order process of cherry pick with return type 'GitMonad' which uses 'ExceptT' and 'GitMonad' for error handling.
-}
processCherryPick
  :: (AppState, GitMonad m)
  => "dataDir" :! FilePath
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "token" :! Text
  -> "srcNum" :! Int
  -> "target" :! Text
  -> "sha" :! Text
  -> m BackportResult
processCherryPick (Arg dataDir) (Arg owner) (Arg repo) (Arg cloneUrl) (Arg token) (Arg srcNum) (Arg target) (Arg sha) = do
  path <-
    ensureClone
      ! #dataDir dataDir
      ! #owner owner
      ! #repo repo
      ! #cloneUrl cloneUrl
      ! #token token

  let branch = backportBranchName srcNum target
      headerArgs = authHeaderArgs token
      name = ?st.config.identityName
      email = ?st.config.identityEmail

  setGitIdentity path name email

  bestEffortGit path ["branch", "-D", branch]
  void $ requireGit (type Checkout) path ["checkout", "-b", branch, "origin/" <> T.unpack target]

  parents <- parentCount path sha
  let pickArgs
        | parents > 1 = ["cherry-pick", "-x", "-m", "1", T.unpack sha]
        | otherwise = ["cherry-pick", "-x", T.unpack sha]

  pickResult <- withGit path pickArgs
  case pickResult of
    Right _ -> do
      void $ requireGit (type Push) path (headerArgs <> ["push", "-f", "origin", branch])
      pure $ BackportPushed path $ T.pack branch
    Left conflictOutput -> do
      bestEffortGit path ["cherry-pick", "--abort"]
      bestEffortGit path ["checkout", T.unpack target]
      bestEffortGit path ["branch", "-D", branch]
      pure $ BackportConflict conflictOutput

{- | This is the main function of 'Git.Backport' module for backporting.
It calls 'processCherryPick' and transfers it to 'processBackport' function from 'Events.Backport' module.
-}
cherryPick
  :: (AppState, MonadIO m)
  => "dataDir" :! FilePath
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "token" :! Text
  -> "srcNum" :! Int
  -> "target" :! Text
  -> "sha" :! Text
  -> m (Either GitError BackportResult)
cherryPick dataDir owner repo cloneUrl token srcNum target sha =
  liftIO . runExceptT $ action
 where
  action :: ExceptT GitError IO BackportResult
  action = processCherryPick dataDir owner repo cloneUrl token srcNum target sha
