{-# LANGUAGE RequiredTypeArguments #-}

module Database.Seed.Handlers where

import Control.Monad (void)
import Database (getBy, upsert)
import Database.Persist (Entity (..))
import Database.Persist qualified as DB
import Database.Seed.Operations
import Database.Seed.Types
import Database.Types
import Kotiba.Prelude
import System.IO (hPutStrLn, stderr)

-- | Upsert a role entity and cache its generated database ID.
seedRole :: (AppState, MonadIO m) => SeedRole -> SeedM m ()
seedRole SeedRole{..} = do
  existing <- getBy (type (Entity Role)) (UniqueRoleName rName)
  k <- upsert existing [] Role{roleName = rName}
  insertMap rName k (.roleMap) (\m s -> s{roleMap = m})

-- | Upsert a user entity and cache its ID.
seedUser :: (AppState, MonadIO m) => SeedUser -> SeedM m ()
seedUser SeedUser{..} = do
  mRid <- lookupRef uRole "role" (.roleMap)
  case mRid of
    Nothing -> liftIO $ hPutStrLn stderr $ "Seed: unknown role for user " <> show uUsername
    Just rid -> do
      existing <- getBy (type (Entity User)) (UniqueUserFrId uFrId)
      k <-
        upsert
          existing
          [ UserLogin DB.=. uLogin
          , UserUsername DB.=. uUsername
          , UserRole DB.=. rid
          ]
          User{userLogin = uLogin, userUsername = uUsername, userFrId = uFrId, userRole = rid}
      insertMap uUsername k (.userMap) (\m s -> s{userMap = m})

-- | Upsert a repository entity and cache its generated database ID.
seedRepository :: (AppState, MonadIO m) => SeedRepository -> SeedM m ()
seedRepository SeedRepository{..} = do
  existing <- getBy (type (Entity Repository)) (UniqueRepositoryFrRepoId pId)
  k <-
    upsert
      existing
      [ RepositoryRepoUrl DB.=. pUrl
      , RepositoryRepoName DB.=. pName
      ]
      Repository{repositoryFrRepoId = pId, repositoryRepoUrl = pUrl, repositoryRepoName = pName}
  insertMap pName k (.repoMap) (\m s -> s{repoMap = m})

-- | Upsert a repository contributor association requiring resolved repo, user, and role IDs.
seedContributor :: (AppState, MonadIO m) => SeedContributor -> SeedM m ()
seedContributor SeedContributor{..} = do
  mRid <- lookupRef cRepo "repository" (.repoMap)
  mUid <- lookupRef cUser "user" (.userMap)
  mRoleid <- lookupRef cRole "role" (.roleMap)
  case (mRid, mUid, mRoleid) of
    (Just rid, Just uid, Just roleid) -> do
      existing <- getBy (type (Entity RepoContributors)) (UniqueRepoContributor rid uid)
      void
        $ upsert
          existing
          [RepoContributorsRole DB.=. roleid]
          RepoContributors{repoContributorsRepoId = rid, repoContributorsUserId = uid, repoContributorsRole = roleid}
    _ -> logMissingRef ("contributor " <> show cUser) cRepo
