{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RequiredTypeArguments #-}
{-# LANGUAGE TypeOperators #-}

module Git.Repo
  ( repoPath
  , ensureClone
  , parentCount
  , setGitIdentity
  ) where

import Control.Monad (void)
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as T
import Git.Core
import Kotiba.Prelude
import Named
import System.Directory (createDirectoryIfMissing, doesDirectoryExist)
import System.FilePath (takeDirectory, (</>))

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
  -> m FilePath
ensureClone (Arg dataDir) (Arg owner) (Arg repo) (Arg cloneUrl) = do
  let path = repoPath dataDir owner repo
  exists <- liftIO $ doesDirectoryExist path
  if exists then
    void $ requireGit (type Fetch) path ["fetch", "origin"]
  else do
    liftIO $ createDirectoryIfMissing True $ takeDirectory path
    void $ requireGit (type Clone) (takeDirectory path) ["clone", T.unpack cloneUrl, path]
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
