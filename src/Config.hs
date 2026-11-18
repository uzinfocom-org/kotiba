{-# LANGUAGE DerivingVia #-}

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

type BotConfig :: Type
data BotConfig = BotConfig
  { login :: !Text
  , frId :: !Int
  , token :: !FilePath
  , name :: !Text
  , email :: !Text
  }
  deriving (Eq, Generic, Show)
  deriving (FromValue) via GenericTomlTable BotConfig

type OrgConfig :: Type
data OrgConfig = OrgConfig
  { webhookSecret :: !FilePath
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
  , seedFile :: Wear t f FilePath
  , orgs :: Wear t f (Map Text OrgConfig)
  }
  deriving (Generic)

instance BareB Config
instance FunctorB (Config Covered)
instance TraversableB (Config Covered)
instance ApplicativeB (Config Covered)

type CanonicalConfig = Config Bare Identity
type ParsedConfig = Config Covered Maybe

deriving stock instance Eq CanonicalConfig
deriving stock instance Show CanonicalConfig

deriving via GenericTomlTable ParsedConfig instance FromValue ParsedConfig

defaults :: ParsedConfig
defaults = emptyConfig{port = Just 8080, databasePoolSize = Just 10}
