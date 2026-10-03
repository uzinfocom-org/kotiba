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

-- | A merged PR is 'StateMerged', never 'StateClosed'. A reopened PR is just open again.
data PullRequestState = StateOpen | StateClosed | StateMerged
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PullRequestState"

{- | What happened in one delivery. Constructors are stored as text by name,
so renaming one after real data exists orphans old rows.
-}
data PREventKind
  = PROpened
  | PRReopened
  | PRClosed
  | PRMerged
  | PRSynchronized
  | PREdited
  | PRAssigned
  | PRUnassigned
  | PRReviewRequested
  | PRReviewApproved
  | PRReviewRejected
  | PRReviewCommented
  | PRLabelChanged
  | PRMilestoned
  | PROther
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PREventKind"

-- | How far the worker got with an event.
data PREventStatus = EventReceived | EventDone | EventFailed
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PREventStatus"

-- | Forgejo's changed-file status. Anything unknown maps to 'FileOther'.
data PullRequestFileStatus
  = FileAdded
  | FileChanged
  | FileDeleted
  | FileRenamed
  | FileCopied
  | FileUnchanged
  | FileOther
  deriving stock (Eq, Generic, Read, Show)
  deriving anyclass (FromJSON, ToJSON)

derivePersistField "PullRequestFileStatus"

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
  PullRequest sql=pull_requests
    repository RepositoryId
    number Int
    author UserId
    title Text
    state PullRequestState
    draft Bool
    baseBranch Text
    openedAt UTCTime
    closedAt UTCTime Maybe
    mergedAt UTCTime Maybe
    mergedBy UserId Maybe
    updatedAt UTCTime
    UniquePullRequest repository number
    deriving Eq
  PullRequestEvent sql=pull_request_events
    deliveryId Text
    pullRequest PullRequestId
    kind PREventKind
    actor UserId
    occurredAt UTCTime
    receivedAt UTCTime default=now()
    status PREventStatus
    UniquePullRequestEventDeliveryId deliveryId
    deriving Eq
  PullRequestFile sql=pull_request_files
    pullRequest PullRequestId
    filename Text
    status PullRequestFileStatus
    UniquePullRequestFile pullRequest filename
    deriving Eq
  PullRequestCommit sql=pull_request_commits
    pullRequest PullRequestId
    sha Text
    author UserId Maybe -- Nothing when the git email matches no Forgejo user
    authorName Text
    authoredAt UTCTime
    isMerge Bool
    UniquePullRequestCommit pullRequest sha
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

type PullRequestCommit :: Type
type PullRequestCommitId :: Type

deriving stock instance Generic PullRequestCommit
deriving stock instance Show PullRequestCommit
deriving anyclass instance FromJSON PullRequestCommit
deriving anyclass instance ToJSON PullRequestCommit

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
