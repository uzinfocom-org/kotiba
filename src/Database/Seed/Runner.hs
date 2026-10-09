module Database.Seed.Runner where

import Control.Monad (unless, when)
import Control.Monad.State (evalStateT)
import Data.Aeson (eitherDecodeFileStrict)
import Data.Time (UTCTime)
import Database.Seed.Error (SeedError (..))
import Database.Seed.Handlers
import Database.Seed.Types
import Kotiba.Prelude
import System.Directory (doesFileExist, getModificationTime)
import Text.Read (readMaybe)

-- | Run the full seeding pipeline starting with empty ID maps.
applySeed :: (AppState, MonadIO m, MonadError SeedError m) => SeedData -> m ()
applySeed sd =
  evalStateT
    ( do
        mapM_ seedRole sd.roles
        mapM_ seedUser sd.users
        mapM_ seedRepository sd.repositories
        mapM_ seedContributor sd.repoContributors
    )
    SeedMaps{roleMap = mempty, userMap = mempty, repoMap = mempty}

-- | Safely read the previously stored modification time from disk.
readStoredMtime :: FilePath -> IO (Maybe UTCTime)
readStoredMtime path = do
  exists <- doesFileExist path
  if exists then readMaybe <$> readFile path else pure Nothing

{- | Check if the seed file changed since last run; if so, parse and apply it.
Missing file, broken file or missing reference is an error, the caller decides what to do with it.
-}
seedIfChanged :: (MonadIO m, MonadError SeedError m) => AppSt -> FilePath -> m ()
seedIfChanged st seedPath = do
  exists <- liftIO $ doesFileExist seedPath
  unless exists $ throwError $ SeedFileNotFound seedPath

  mtime <- liftIO $ getModificationTime seedPath
  storedMtime <- liftIO $ readStoredMtime mtimePath

  when (mtime `notElem` storedMtime) $ do
    liftIO $ putStrLn "Seed: file changed, applying..."
    sd <- eitherDecodeFileStrict seedPath <!!> SeedParseError
    let ?st = st
    applySeed sd
    liftIO $ writeFile mtimePath (show mtime)
    liftIO $ putStrLn "Seed: done"
 where
  mtimePath = seedPath <> ".mtime"
