module Database.Seed.Operations where

import Control.Monad.State (StateT, gets, modify)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Database.Seed.Error
import Database.Seed.Types (SeedMaps)
import Kotiba.Prelude

-- | Look up a cached database ID from the state map by its name key.
lookupRef
  :: (MonadError SeedError m)
  => Text
  -> String
  -> Text
  -> (SeedMaps -> Map Text k)
  -> StateT SeedMaps m k
lookupRef owner entity key selector =
  gets (Map.lookup key . selector)
    !? SeedMissingReference
      { entity = (entity <> " " <> show key)
      , name = owner
      }

-- | Generic combinator to insert a resolved key into the appropriate state map.
insertMap
  :: (Monad m) => Text -> k -> (SeedMaps -> Map Text k) -> (Map Text k -> SeedMaps -> SeedMaps) -> StateT SeedMaps m ()
insertMap name k getter setter =
  modify \s -> setter (Map.insert name k $ getter s) s
