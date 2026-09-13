{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module RNA.Core where

import Control.Monad (unless)
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Text qualified as T
import Git.Core (authHeaderArgs)
import Kotiba.Prelude
import Named
import RNA.StorageMode (StorageMode (..))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, removePathForcibly)
import System.FilePath ((</>))
import System.Process.Typed

newtype RnaError = RnaGenerateFailed Text
  deriving stock (Show)

type RnaMonad m = (MonadIO m, MonadError RnaError m)

rnaBinary :: FilePath
rnaBinary = "release-notes-assistant"

storageArgs :: StorageMode -> [String]
storageArgs = \case
  SMFile path -> ["--storage", "file", "--storage-location", path]
  SMMilestone name -> ["--storage", "milestone", "--storage-location", T.unpack name]
  SMRelease -> ["--storage", "release"]

ensureMirrorClone :: (RnaMonad m) => FilePath -> Text -> Text -> m ()
ensureMirrorClone workdir cloneUrl token = do
  let clonePath = workdir </> "clone"
  liftIO $ createDirectoryIfMissing True workdir
  valid <- liftIO $ do
    (ec, _, _) <- readProcess (proc "git" ["-C", clonePath, "rev-parse", "--git-dir"])
    pure (ec == ExitSuccess)
  unless valid $ do
    liftIO $ removePathForcibly clonePath
    (ec, out, err) <-
      readProcess . proc "git" $ authHeaderArgs token <> ["clone", "--mirror", T.unpack cloneUrl, clonePath]
    case ec of
      ExitFailure _ -> throwError . RnaGenerateFailed . T.pack . BL8.unpack $ out <> err
      ExitSuccess -> pure ()

generateReleaseNotes
  :: (RnaMonad m)
  => "dataDir" :! FilePath
  -> "forgejoUrl" :! Text
  -> "owner" :! Text
  -> "repo" :! Text
  -> "cloneUrl" :! Text
  -> "token" :! Text
  -> "tag" :! Text
  -> "storage" :! StorageMode
  -> m ReleaseNotesResult
generateReleaseNotes (Arg dataDir) (Arg forgejoUrl) (Arg owner) (Arg repo) (Arg cloneUrl) (Arg token) (Arg tag) (Arg storage) = do
  let workdir = dataDir </> "release-notes" </> T.unpack owner </> T.unpack repo
  ensureMirrorClone workdir cloneUrl token
  let args =
        [ "--forgejo-url", T.unpack forgejoUrl
        , "--repository", T.unpack owner <> "/" <> T.unpack repo
        , "--token", T.unpack token
        , "--workdir", workdir
        ]
          <> storageArgs storage
          <> ["release", T.unpack tag]
  liftIO $ createDirectoryIfMissing True workdir
  (ec, out, err) <- readProcess $ proc rnaBinary args
  case ec of
    ExitFailure _ -> throwError . RnaGenerateFailed . T.pack . BL8.unpack $ out <> err
    ExitSuccess -> pure $ case storage of
      SMFile path -> NotesFile path
      SMMilestone _ -> NotesInMilestone
      SMRelease -> NotesInRelease

data ReleaseNotesResult = NotesFile FilePath | NotesInMilestone | NotesInRelease
