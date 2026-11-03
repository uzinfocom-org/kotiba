{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Git.Backport
  ( BackportResult (..)
  , cherryPick
  ) where

import Control.Monad (void)
import Data.Text qualified as T
import Git.Core
import Git.Repo
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
It requires all arguments of 'cherryPick' function in order process of cherry pick with return type 'GitMonad', which uses 'ExceptT' for errors and 'ReaderT' for GitEnv.
Process is: clone or fetch, create backport branch from target, cherry-pick and push.
If cherry-pcik conflicts, branch is cleaned up and 'BackportConflict' is returned.
-}
processCherryPick
  :: (AppState, GitMonad m)
  => "dataDir" :! FilePath
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "srcNum" :! Int
  -> "target" :! Text
  -> "sha" :! Text
  -> m BackportResult
processCherryPick (Arg dataDir) (Arg owner) (Arg repo) (Arg cloneUrl) (Arg srcNum) (Arg target) (Arg sha) = do
  path <-
    ensureClone
      ! #dataDir dataDir
      ! #owner owner
      ! #repo repo
      ! #cloneUrl cloneUrl

  let branch = backportBranchName srcNum target
      name = ?st.config.identityName
      email = ?st.config.identityEmail

  setGitIdentity path name email

  bestEffortGit path ["branch", "-D", branch]
  void $ requireGit (type Checkout) path ["checkout", "-b", branch, "origin/" <> T.unpack target]

  parents <- parentCount path sha
  let pickArgs
        | parents > 1 = ["cherry-pick", "-x", "-m", "1", T.unpack sha]
        | otherwise = ["cherry-pick", "-x", T.unpack sha]

  pickResult <- tryGit (type CherryPick) path pickArgs
  case pickResult of
    Right _ -> do
      void $ requireGit (type Push) path ["push", "-f", "origin", branch]
      pure $ BackportPushed path $ T.pack branch
    Left conflictOutput -> do
      bestEffortGit path ["cherry-pick", "--abort"]
      bestEffortGit path ["checkout", T.unpack target]
      bestEffortGit path ["branch", "-D", branch]
      pure $ BackportConflict conflictOutput

{- | This is the main function of 'Git.Backport' module for backporting.
It created 'GitEnv' from Forgejo token, runs 'processCherryPick' via 'runGitM' and transfers result to 'processBackport' function from 'Events.Backport' module.
-}
cherryPick
  :: (AppState, MonadIO m)
  => "dataDir" :! FilePath
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "srcNum" :! Int
  -> "target" :! Text
  -> "sha" :! Text
  -> m (Either GitError BackportResult)
cherryPick dataDir owner repo cloneUrl srcNum target sha = do
  env <- mkGitEnv ?st.config.forgejoToken
  runGitM env $ processCherryPick dataDir owner repo cloneUrl srcNum target sha
