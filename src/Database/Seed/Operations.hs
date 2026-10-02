module Database.Seed.Operations where

import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.State (StateT, gets, modify)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Database.Seed.Types (SeedMaps)
import System.IO (hPutStrLn, stderr)

-- | Look up a cached database ID from the state map by its name key.
lookupRef :: (Monad m) => Text -> String -> (SeedMaps -> Map Text k) -> StateT SeedMaps m (Maybe k)
lookupRef keyName _ selector = gets (Map.lookup keyName . selector)

-- | Log a standardized warning when a foreign reference cannot be resolved.
logMissingRef :: (MonadIO m) => String -> Text -> m ()
logMissingRef entityName name =
  liftIO . hPutStrLn stderr $ "Seed: could not resolve " <> entityName <> " for " <> show name

-- | Generic combinator to insert a resolved key into the appropriate state map.
insertMap
  :: (Monad m) => Text -> k -> (SeedMaps -> Map Text k) -> (Map Text k -> SeedMaps -> SeedMaps) -> StateT SeedMaps m ()
insertMap name k getter setter =
  modify \s -> setter (Map.insert name k $ getter s) s
