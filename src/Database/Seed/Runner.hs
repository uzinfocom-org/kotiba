module Database.Seed.Runner where

import Control.Monad (unless, when)
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.State (evalStateT)
import Data.Aeson (eitherDecodeFileStrict)
import Data.Time (UTCTime)
import Database.Seed.Handlers
import Database.Seed.Types
import Kotiba.Prelude (AppSt (..), AppState)
import System.Directory (doesFileExist, getModificationTime)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

-- | Run the full seeding pipeline starting with empty ID maps.
applySeed :: (AppState, MonadIO m) => SeedData -> m ()
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

-- | Check if the seed file changed since last run; if so, parse and apply it.
seedIfChanged :: AppSt -> FilePath -> IO ()
seedIfChanged st seedPath = do
  let mtimePath = seedPath <> ".mtime"
  exists <- doesFileExist seedPath
  unless exists $ hPutStrLn stderr $ "Seed: file not found: " <> seedPath
  when exists $ do
    mtime <- getModificationTime seedPath
    storedMtime <- readStoredMtime mtimePath
    when (mtime `notElem` storedMtime) $ do
      putStrLn "Seed: file changed, applying..."
      result <- eitherDecodeFileStrict seedPath
      case result of
        Left err -> hPutStrLn stderr $ "Seed: parse error: " <> err
        Right sd -> do
          let ?st = st
          applySeed sd
          writeFile mtimePath (show mtime)
          putStrLn "Seed: done"
