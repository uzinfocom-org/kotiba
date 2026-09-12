{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE OverloadedStrings #-}

module RNA.StorageMode (StorageMode (..)) where

import Data.Text (Text)
import Data.Text qualified as T
import GHC.Generics (Generic)
import Toml.Schema (FromValue (..), ToValue (..))
import Toml.Schema.Generic (GenericTomlTable (..))
import Toml.Schema qualified as Toml

data StorageMode
  = SMFile FilePath
  | SMMilestone Text
  | SMRelease
  deriving stock (Eq, Show)

data StorageModeRow = StorageModeRow
  { mode :: Text
  , location :: Maybe Text
  }
  deriving stock (Generic)
  deriving (FromValue, ToValue) via GenericTomlTable StorageModeRow

toRow :: StorageMode -> StorageModeRow
toRow = \case
  SMFile path -> StorageModeRow{mode = "file", location = Just $ T.pack path}
  SMMilestone name -> StorageModeRow{mode = "milestone", location = Just name}
  SMRelease -> StorageModeRow{mode = "release", location = Nothing}

fromRow :: StorageModeRow -> Either String StorageMode
fromRow StorageModeRow{..} = case mode of
  "file" -> maybe (Left "release-notes storage mode \"file\" requires a location") (Right . SMFile . T.unpack) location
  "milestone" -> maybe (Left "release-notes storage mode \"milestone\" requires a location") (Right . SMMilestone) location
  "release" -> Right SMRelease
  other -> Left $ "unknown release-notes storage mode: " <> T.unpack other

instance ToValue StorageMode where
  toValue = toValue . toRow

instance FromValue StorageMode where
  fromValue v = do
    row <- fromValue v
    either fail pure $ fromRow row
