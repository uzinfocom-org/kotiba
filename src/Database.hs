{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Database where

import Data.Aeson (FromJSON, ToJSON)
import Data.Kind (Type)
import Data.Pool (Pool)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import Data.UUID (UUID)
import Data.UUID qualified as UUID
import Database.Esqueleto.Experimental
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

share
  [mkPersist sqlSettings, mkMigrate "migrateAll"]
  [persistLowerCase|
  Maintainer sql=maintainers
    login Text
    username Text
    frId Int -- Forgejouser id
    deriving Eq
  Repository sql=repositories
    frRepoId Int
    repoUrl Text -- repository.clone_url
    repoName Text -- repository.full_name
    deriving Eq
  Jobs sql=jobs
    Id UUID default=gen_random_uuid()
  RepoMaintainers sql=repository_maintainers
    repoId RepositoryId
    mnId MaintainerId
    deriving Eq
|]

type Maintainer :: Type
type MaintainerId :: Type

deriving stock instance Generic Maintainer
deriving stock instance Show Maintainer
deriving anyclass instance FromJSON Maintainer

type Repository :: Type
type RepositoryId :: Type

deriving stock instance Generic Repository
deriving stock instance Show Repository
deriving anyclass instance FromJSON Repository
deriving anyclass instance ToJSON Repository
