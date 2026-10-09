module Database.Seed.Types where

import Control.Monad.State (StateT)
import Data.Aeson (FromJSON (..), genericParseJSON)
import Data.Aeson.Types (Options (..), defaultOptions)
import Data.Map.Strict (Map)
import Database.Seed.Error
import Database.Types
import Kotiba.Prelude

-- | Haskell field name -> key used in seed.json.
jsonKey :: String -> String
jsonKey = \case
  "rName" -> "name"
  "uLogin" -> "login"
  "uUsername" -> "username"
  "uFrId" -> "frId"
  "uRole" -> "role"
  "pId" -> "frRepoId"
  "pUrl" -> "repoUrl"
  "pName" -> "repoName"
  "cRepo" -> "repoName"
  "cUser" -> "username"
  "cRole" -> "role"
  other -> other

seedOptions :: Options
seedOptions = defaultOptions{fieldLabelModifier = jsonKey}

-- | Represents a single role definition to seed.
newtype SeedRole = SeedRole
  { rName :: Text
  }
  deriving stock (Generic)

instance FromJSON SeedRole where
  parseJSON = genericParseJSON seedOptions

-- | Represents a user record to seed.
data SeedUser = SeedUser
  { uLogin :: !Text
  , uUsername :: !Text
  , uFrId :: !FrId
  , uRole :: !Text
  }
  deriving stock (Generic)

instance FromJSON SeedUser where
  parseJSON = genericParseJSON seedOptions

-- | Represents a repository record to seed.
data SeedRepository = SeedRepository
  { pId :: !FrId
  , pUrl :: !Text
  , pName :: !Text
  }
  deriving stock (Generic)

instance FromJSON SeedRepository where
  parseJSON = genericParseJSON seedOptions

-- | Represents a contributor record to seed.
data SeedContributor = SeedContributor
  { cRepo :: !Text
  , cUser :: !Text
  , cRole :: !Text
  }
  deriving stock (Generic)

instance FromJSON SeedContributor where
  parseJSON = genericParseJSON seedOptions

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
type SeedM :: (Type -> Type) -> Type -> Type
type SeedM m = StateT SeedMaps m

type SeedMonad :: (Type -> Type) -> Constraint
type SeedMonad m =
  (AppState, MonadIO m, MonadError SeedError m)
