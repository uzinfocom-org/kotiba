{-# LANGUAGE DerivingVia #-}

module Config where

import Data.ByteString qualified as BS
import Data.Kind (Type)
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8)
import GHC.Generics (Generic)
import Toml qualified
import Toml.Schema (FromValue, ToTable, ToValue)
import Toml.Schema.Generic (GenericTomlTable (..))
import Toml.Schema.Matcher (Result (..))

type Config :: Type
data Config = Config
  { dataDir :: !FilePath
  , port :: !Int
  , database :: !Text
  , databasePoolSize :: !Int
  , forgejoUrl :: !Text
  , forgejoToken :: !Text
  }
  deriving (Eq, Generic, Show)
  deriving (FromValue, ToTable, ToValue) via GenericTomlTable Config

loadConfig :: FilePath -> IO (Result Toml.DecodeError Config)
loadConfig filepath = do
  print $ "Configuration loaded from: " <> filepath
  Toml.decode' . decodeUtf8 <$> BS.readFile filepath
