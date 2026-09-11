{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE RequiredTypeArguments #-}

module Database.Seed where

import Control.Monad (unless, void, when)
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.State (StateT, evalStateT, gets, modify)
import Data.Aeson (FromJSON, eitherDecodeFileStrict)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime)
import Database (getBy, upsert)
import Database.Persist (Entity (..))
import Database.Persist qualified as DB
import Database.Types
import GHC.Generics (Generic)
import Kotiba.Prelude (AppSt (..), AppState)
import System.Directory (doesFileExist, getModificationTime)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

newtype SeedRole = SeedRole {name :: Text}
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data SeedUser = SeedUser
  { login :: !Text
  , username :: !Text
  , frId :: !Int
  , role :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data SeedRepository = SeedRepository
  { frRepoId :: !Int
  , repoUrl :: !Text
  , repoName :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data SeedContributor = SeedContributor
  { repoName :: !Text
  , username :: !Text
  , role :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

data SeedData = SeedData
  { roles :: ![SeedRole]
  , users :: ![SeedUser]
  , repositories :: ![SeedRepository]
  , repoContributors :: ![SeedContributor]
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- Resolved DB IDs accumulated during seeding

data SeedMaps = SeedMaps
  { roleMap :: Map Text RoleId
  , userMap :: Map Text UserId
  , repoMap :: Map Text RepositoryId
  }

type SeedM m = StateT SeedMaps m

seedRole :: (AppState, MonadIO m) => SeedRole -> SeedM m ()
seedRole sr = do
  existing <- getBy (type (Entity Role)) (UniqueRoleName sr.name)
  k <- upsert existing [] Role{roleName = sr.name}
  modify \s -> s{roleMap = Map.insert sr.name k s.roleMap}

seedUser :: (AppState, MonadIO m) => SeedUser -> SeedM m ()
seedUser su = do
  mRid <- gets (Map.lookup su.role . (.roleMap))
  case mRid of
    Nothing ->
      liftIO $ hPutStrLn stderr $ "Seed: unknown role for user " <> show su.username
    Just rid -> do
      existing <- getBy (type (Entity User)) (UniqueUserFrId su.frId)
      k <-
        upsert
          existing
          [ UserLogin DB.=. su.login
          , UserUsername DB.=. su.username
          , UserRole DB.=. rid
          ]
          User{userLogin = su.login, userUsername = su.username, userFrId = su.frId, userRole = rid}
      modify \s -> s{userMap = Map.insert su.username k s.userMap}

seedRepository :: (AppState, MonadIO m) => SeedRepository -> SeedM m ()
seedRepository sr = do
  existing <- getBy (type (Entity Repository)) (UniqueRepositoryFrRepoId sr.frRepoId)
  k <-
    upsert
      existing
      [ RepositoryRepoUrl DB.=. sr.repoUrl
      , RepositoryRepoName DB.=. sr.repoName
      ]
      Repository{repositoryFrRepoId = sr.frRepoId, repositoryRepoUrl = sr.repoUrl, repositoryRepoName = sr.repoName}
  modify \s -> s{repoMap = Map.insert sr.repoName k s.repoMap}

seedContributor :: (AppState, MonadIO m) => SeedContributor -> SeedM m ()
seedContributor sc = do
  mRid <- gets (Map.lookup sc.repoName . (.repoMap))
  mUid <- gets (Map.lookup sc.username . (.userMap))
  mRoleid <- gets (Map.lookup sc.role . (.roleMap))
  case (mRid, mUid, mRoleid) of
    (Just rid, Just uid, Just roleid) -> do
      existing <- getBy (type (Entity RepoContributors)) (UniqueRepoContributor rid uid)
      void
        $ upsert
          existing
          [RepoContributorsRole DB.=. roleid]
          RepoContributors{repoContributorsRepoId = rid, repoContributorsUserId = uid, repoContributorsRole = roleid}
    _ ->
      liftIO
        $ hPutStrLn stderr
        $ "Seed: could not resolve contributor "
          <> show sc.username
          <> " / "
          <> show sc.repoName

applySeed :: (AppState, MonadIO m) => SeedData -> m ()
applySeed sd =
  evalStateT
    ( do
        mapM_ seedRole sd.roles
        mapM_ seedUser sd.users
        mapM_ seedRepository sd.repositories
        mapM_ seedContributor sd.repoContributors
    )
    SeedMaps{roleMap = mempty, userMap = mempty, repoMap = mempty}

readStoredMtime :: FilePath -> IO (Maybe UTCTime)
readStoredMtime path = do
  exists <- doesFileExist path
  if exists
    then readMaybe <$> readFile path
    else pure Nothing

seedIfChanged :: AppSt -> FilePath -> IO ()
seedIfChanged st seedPath = do
  let mtimePath = seedPath <> ".mtime"
  exists <- doesFileExist seedPath
  unless exists
    $ hPutStrLn stderr
    $ "Seed: file not found: " <> seedPath
  when exists $ do
    mtime <- getModificationTime seedPath
    storedMtime <- readStoredMtime mtimePath
    when (mtime `notElem` storedMtime) $ do
      putStrLn "Seed: file changed, applying..."
      (result :: Either String SeedData) <- eitherDecodeFileStrict seedPath
      case result of
        Left err -> hPutStrLn stderr $ "Seed: parse error: " <> err
        Right sd -> do
          let ?st = st
          applySeed sd
          writeFile mtimePath (show mtime)
          putStrLn "Seed: done"
