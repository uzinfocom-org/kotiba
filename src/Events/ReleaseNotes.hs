{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators #-}

module Events.ReleaseNotes where

import Control.Monad (unless, when)
import Control.Monad.Except (runExceptT)
import Data.Int (Int64 (..))
import Data.Text.IO qualified as TIO
import Database qualified as DB
import Database.Types (ReleaseNotesStatus (..))
import Forgejo.Methods.Release (editRelease)
import Forgejo.Types.Common (RepoId (..))
import Forgejo.Types.Release (HookReleaseAction (..), Release (..), ReleasePayload (..))
import Forgejo.Types.EditReleaseOption (EditReleaseOption (..))
import Forgejo.Types.Repository (Repository (..))
import Forgejo.Types.User (User (..))
import Kotiba.Prelude
import Named
import RNA.Core
import Servant (Handler)

processReleasePublished :: (AppState) => ReleasePayload -> Handler ()
processReleasePublished ReleasePayload{..} = do
  let owner = rpRepository.repoOwner.userLogin
      repo = rpRepository.repoName
      cloneUrl = rpRepository.repoCloneUrl
      RepoId repoIdRaw = rpRepository.repoId
      repoFrId = fromIntegral @Int64 repoIdRaw
      tag = rpRelease.relTagName
      releaseId = rpRelease.relId

  when (rpAction == RelPublished) $ do
    exists <- DB.releaseNotesExists repoFrId tag
    unless exists $ do
      result <- liftIO . runExceptT $
        generateReleaseNotes
          ! #dataDir ?st.config.dataDir
          ! #forgejoUrl ?st.config.forgejoUrl
          ! #owner owner
          ! #repo repo
          ! #cloneUrl cloneUrl
          ! #token ?st.config.forgejoToken
          ! #tag tag
          ! #storage ?st.config.releaseNotesStorage
      case result of
        Left rnaErr -> do
          liftIO $ printer rnaErr
          DB.recordReleaseNotes repoFrId tag RNError
        Right (NotesFile f) -> do
          content <- liftIO $ TIO.readFile f
          let opts =
                EditReleaseOption
                  { body = content
                  , draft = rpRelease.relDraft
                  , hideArchiveLinks = rpRelease.relHideArchiveLinks
                  , name = rpRelease.relName
                  , prerelease = rpRelease.relPrerelease
                  , tagName = rpRelease.relTagName
                  , targetCommitish = rpRelease.relTargetCommitish
                  }
          _ <- tryForgejo $ editRelease owner repo rpRelease.relId opts
          DB.recordReleaseNotes repoFrId tag RNPosted
        Right NotesInMilestone -> DB.recordReleaseNotes repoFrId tag RNPosted
        Right _ -> DB.recordReleaseNotes repoFrId tag RNPosted
