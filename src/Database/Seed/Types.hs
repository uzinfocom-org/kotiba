{-# LANGUAGE OverloadedStrings #-}

module Database.Seed.Types where

import Control.Monad.State (StateT)
import Data.Aeson (FromJSON)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Database.Types
import GHC.Generics (Generic)

-- | Represents a single role definition to seed.
newtype SeedRole = SeedRole
  { rName :: Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- | Represents a user record to seed.
data SeedUser = SeedUser
  { uLogin :: !Text
  , uUsername :: !Text
  , uFrId :: !Int
  , uRole :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- | Represents a repository record to seed.
data SeedRepository = SeedRepository
  { pId :: !Int
  , pUrl :: !Text
  , pName :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- | Represents a contributor record to seed.
data SeedContributor = SeedContributor
  { cRepo :: !Text
  , cUser :: !Text
  , cRole :: !Text
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- | Root container holding all parsed seed lists from the file.
data SeedData = SeedData
  { roles :: ![SeedRole]
  , users :: ![SeedUser]
  , repositories :: ![SeedRepository]
  , repoContributors :: ![SeedContributor]
  }
  deriving stock (Generic)
  deriving anyclass (FromJSON)

-- | In-memory lookup maps caching generated database IDs during seeding.
data SeedMaps = SeedMaps
  { roleMap :: !(Map Text RoleId)
  , userMap :: !(Map Text UserId)
  , repoMap :: !(Map Text RepositoryId)
  }

-- | State monad transformer specialized for threading SeedMaps through seed actions.
type SeedM m = StateT SeedMaps m
