{-# LANGUAGE DerivingVia #-}

-- | Shape of the config file. See "Config.Load" for how it's decoded.
module Config where

import Barbies
import Barbies.Bare
import Config.Load
import Data.Functor.Identity (Identity)
import Data.Kind (Type)
import Data.Map (Map)
import Data.Text (Text)
import GHC.Generics (Generic)
import Toml.Schema (FromValue)
import Toml.Schema.Generic (GenericTomlTable (..))

-- | The account Kotiba acts as inside one org.
type BotConfig :: Type
data BotConfig = BotConfig
  { login :: !Text
  , frId :: !Int
  , token :: !FilePath
  -- ^ path to the token file
  , name :: !Text
  -- ^ git author
  , email :: !Text
  -- ^ git author
  }
  deriving (Eq, Generic, Show)
  deriving (FromValue) via GenericTomlTable BotConfig

type OrgConfig :: Type
data OrgConfig = OrgConfig
  { webhookSecret :: !FilePath
  -- ^ path to the secret file, can't be empty
  , bot :: !BotConfig
  }
  deriving (Eq, Generic, Show)
  deriving (FromValue) via GenericTomlTable OrgConfig

type Config :: Type -> (Type -> Type) -> Type
data Config t f = Config
  { dataDir :: Wear t f FilePath
  , port :: Wear t f Int
  , database :: Wear t f Text
  , databasePoolSize :: Wear t f Int
  , forgejoUrl :: Wear t f Text
  -- ^ one instance for all orgs
  , seedFile :: Wear t f FilePath
  , orgs :: Wear t f (Map Text OrgConfig)
  -- ^ matched with the repo owner login from payloads, ignoring case
  }
  deriving (Generic)

instance BareB Config
instance FunctorB (Config Covered)
instance TraversableB (Config Covered)
instance ApplicativeB (Config Covered)

-- | Everything is there.
type CanonicalConfig = Config Bare Identity

-- | What we read from the file, everything optional.
type ParsedConfig = Config Covered Maybe

deriving stock instance Eq CanonicalConfig
deriving stock instance Show CanonicalConfig

deriving via GenericTomlTable ParsedConfig instance FromValue ParsedConfig

defaults :: ParsedConfig
defaults = emptyConfig{port = Just 8080, databasePoolSize = Just 10}
