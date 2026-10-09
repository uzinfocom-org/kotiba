{-# LANGUAGE RequiredTypeArguments #-}

module Database.Seed.Handlers where

import Control.Monad (void)
import Database
import Database.Persist (Entity (..))
import Database.Persist qualified as DB
import Database.Seed.Error
import Database.Seed.Operations
import Database.Seed.Types
import Database.Types
import Kotiba.Prelude

-- | Upsert a role entity and cache its generated database ID.
seedRole :: (SeedMonad m) => SeedRole -> SeedM m ()
seedRole SeedRole{..} = do
  existing <- getBy (type (Entity Role)) (UniqueRoleName rName)
  k <- upsert existing [] Role{roleName = rName}
  insertMap rName k (.roleMap) (\m s -> s{roleMap = m})

-- | Upsert a user entity and cache its ID.
seedUser :: (SeedMonad m) => SeedUser -> SeedM m ()
seedUser SeedUser{..} = do
  repoId <- lookupRef uUsername "role" uRole (.roleMap)
  existing <- getBy (type (Entity User)) (UniqueUserFrId uFrId)

  k <-
    upsert
      existing
      [ UserLogin DB.=. uLogin
      , UserUsername DB.=. uUsername
      , UserRole DB.=. Just repoId
      ]
      User
        { userLogin = uLogin
        , userUsername = uUsername
        , userFrId = uFrId
        , userRole = Just repoId
        }

  insertMap uUsername k (.userMap) \m s ->
    s{userMap = m}

-- | Upsert a repository entity and cache its generated database ID.
seedRepository :: (SeedMonad m) => SeedRepository -> SeedM m ()
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
seedContributor :: (AppState, MonadIO m, MonadError SeedError m) => SeedContributor -> SeedM m ()
seedContributor SeedContributor{..} = do
  repoId <- lookupRef cUser "repository" cRepo (.repoMap)
  userId <- lookupRef cRepo "user" cUser (.userMap)
  roleId <- lookupRef cUser "role" cRole (.roleMap)
  existing <- getBy (type (Entity RepoContributors)) (UniqueRepoContributor repoId userId)
  void
    $ upsert
      existing
      [RepoContributorsRole DB.=. roleId]
      RepoContributors
        { repoContributorsRepoId = repoId
        , repoContributorsUserId = userId
        , repoContributorsRole = roleId
        }
