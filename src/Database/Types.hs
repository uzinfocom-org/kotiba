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

data PullRequestState = Opened | Reopened | Closed | Merged
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PullRequestState"

data PREventKind = PROpened | PRReopened | PRClosed | PRMerged | Synchronized | Edited | Assigned | Unassigned | ReviewRequested | ReviewApproved | ReviewRejected | ReviewCommented | LabelChanged | Milestoned | Other
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PREventKind"

share
  [mkPersist sqlSettings, mkMigrate "migrateAll"]
  [persistLowerCase|
  User sql=users
    login Text
    username Text
    frId Int -- Forgejouser id
    role RoleId
    UniqueUser login frId
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
    UniqueRole name
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
  PullRequest sql=pull_requests
    repository RepositoryId
    prFrNumber Int
    author UserId
    title Text
    state PullRequestState
    draft Bool
    baseBranch BranchId
    targetBranch BranchId
    openedAt UTCTime default=now()
    closedAt UTCTime Maybe
    mergedAt UTCTime
    mergedBy UserId
    updatedAt UTCTime
    deriving Eq
  PullRequestEvent sql=pull_request_events
    deliveryId Text
    repository RepositoryId
    pullRequest PullRequestId
    kind PREventKind
    actor Text
    occuredAt UTCTime
    receivedAt UTCTime default=now()
    -- status PREventStatus
    UniquePullRequestEvent deliveryId
    deriving Eq
  PullRequestFile sql=pull_request_files
    repository RepositoryId
    pullRequest PullRequestId
    filename Text
    deriving Eq
  PullRequestCommit sql=pull_request_commits
    repository RepositoryId
    pullRequest PullRequestId
    sha Text
    author UserId
    authoredAt UTCTime
    isMerge Bool
    deriving Eq
  Branch sql=branches
    title Text
    createdAt UTCTime default=now()
    updatedAt UTCTime
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

type BackportRecord :: Type
type BackportRecordId :: Type

deriving stock instance Generic BackportRecord
deriving stock instance Show BackportRecord
deriving anyclass instance FromJSON BackportRecord
deriving anyclass instance ToJSON BackportRecord

type PullRequest :: Type
type PullRequestId :: Type

deriving stock instance Generic PullRequest
deriving stock instance Show PullRequest
deriving anyclass instance FromJSON PullRequest
deriving anyclass instance ToJSON PullRequest

type PullRequestEvent :: Type
type PullRequestEventId :: Type

deriving stock instance Generic PullRequestEvent
deriving stock instance Show PullRequestEvent
deriving anyclass instance FromJSON PullRequestEvent
deriving anyclass instance ToJSON PullRequestEvent

type PullRequestFile :: Type
type PullRequestFileId :: Type

deriving stock instance Generic PullRequestFile
deriving stock instance Show PullRequestFile
deriving anyclass instance FromJSON PullRequestFile
deriving anyclass instance ToJSON PullRequestFile

type Branch :: Type
type BranchId :: Type

deriving stock instance Generic Branch
deriving stock instance Show Branch
deriving anyclass instance FromJSON Branch
deriving anyclass instance ToJSON Branch

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
