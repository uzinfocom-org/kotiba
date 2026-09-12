{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Database.Types where

import Data.Aeson (FromJSON, ToJSON)
import Data.Kind (Type)
import Data.Pool (Pool)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import Data.Time (UTCTime)
import Data.UUID (UUID)
import Data.UUID qualified as UUID
import Database.Esqueleto.Experimental
import Database.Persist.Records
import Database.Persist.TH
import GHC.Generics (Generic)
import Web.PathPieces (PathPiece (..))

instance PersistField UUID where
  toPersistValue = PersistText . UUID.toText
  fromPersistValue = \case
    PersistText t -> parseUUID t
    PersistLiteral_ _ bs -> parseUUID $ decodeUtf8 bs
    PersistByteString bs -> parseUUID $ decodeUtf8 bs
    _ -> Left "Expected PersistText or PersistLiteral for UUID"
   where
    parseUUID = maybe (Left "Invalid UUID") Right . UUID.fromText

instance PersistFieldSql UUID where
  sqlType _ = SqlOther "UUID"

instance PathPiece UUID where
  fromPathPiece = UUID.fromText
  toPathPiece = UUID.toText

type PoolSql = Pool SqlBackend

data BackportStatus = BPOpened | BPConflict | BPError
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "BackportStatus"

data ReleaseNotesStatus = RNPosted | RNError
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "ReleaseNotesStatus"

share
  [mkPersist sqlSettings, mkMigrate "migrateAll"]
  [persistLowerCase|
  User sql=users
    login Text
    username Text
    frId Int -- Forgejouser id
    role RoleId
    UniqueUserFrId frId
    deriving Eq
  Repository sql=repositories
    frRepoId Int
    repoUrl Text -- repository.clone_url
    repoName Text -- repository.full_name
    UniqueRepositoryFrRepoId frRepoId
    deriving Eq
  Jobs sql=jobs
    Id UUID default=gen_random_uuid()
  RepoContributors sql=repo_contributors
    repoId RepositoryId
    userId UserId
    role RoleId
    UniqueRepoContributor repoId userId
    deriving Eq
  Role sql=roles
    name Text
    UniqueRoleName name
    deriving Eq
  BackportRecord sql=backport_records
    sourcePrNumber Int
    repoFrId Int
    targetBranch Text
    backportPrNumber Int Maybe
    status BackportStatus
    createdAt UTCTime default=now()
    UniqueBackportRecord sourcePrNumber repoFrId targetBranch
    deriving Eq
  ReleaseNotesRecord sql=release_notes_records
    repoFrId Int
    targetTag Text
    status ReleaseNotesStatus
    createdAt UTCTime default=now()
    UniqueReleaseNotesRecord repoFrId targetTag
    deriving Eq
|]

type User :: Type
type UserId :: Type

deriving stock instance Generic User
deriving stock instance Show User
deriving anyclass instance FromJSON User
deriving anyclass instance ToJSON User

type Repository :: Type
type RepositoryId :: Type

deriving stock instance Generic Repository
deriving stock instance Show Repository
deriving anyclass instance FromJSON Repository
deriving anyclass instance ToJSON Repository

type Role :: Type
type RoleId :: Type

deriving stock instance Generic Role
deriving stock instance Show Role
deriving anyclass instance FromJSON Role
deriving anyclass instance ToJSON Role

deriving stock instance Generic BackportRecord
deriving stock instance Show BackportRecord
deriving anyclass instance FromJSON BackportRecord
deriving anyclass instance ToJSON BackportRecord

genRec ''Role
genRec ''User

deriving stock instance Generic RoleView
deriving stock instance Show RoleView
deriving anyclass instance FromJSON RoleView
deriving anyclass instance ToJSON RoleView

deriving stock instance Generic UserView
deriving stock instance Show UserView
deriving anyclass instance FromJSON UserView
deriving anyclass instance ToJSON UserView

deriving stock instance Generic ReleaseNotesRecord
deriving stock instance Show ReleaseNotesRecord
deriving anyclass instance FromJSON ReleaseNotesRecord
deriving anyclass instance ToJSON ReleaseNotesRecord
