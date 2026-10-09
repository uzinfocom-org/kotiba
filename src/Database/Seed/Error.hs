-- | Errors of seeding. One type for the whole seed package, the message is built in 'seedErrorMessage'.
module Database.Seed.Error where

import Kotiba.Prelude

data SeedError
  = -- | Seed file is not there. We must know it in production, so it's never skipped silently.
    SeedFileNotFound FilePath
  | -- | Seed file is there, but it can't be parsed.
    SeedParseError String
  | -- | Seed refers to something which is not seeded yet (role, repository, user).
    SeedMissingReference
      { entity :: String
      , name :: Text
      }
  | -- | Role "bot" is not in the database, so bots from config can't be synced.
    SeedBotRoleMissing
  deriving stock (Eq, Show)

-- | This function renders 'SeedError' for the log.
seedErrorMessage :: SeedError -> String
seedErrorMessage = \case
  SeedFileNotFound path -> "Seed: file not found: " <> path
  SeedParseError err -> "Seed: parse error: " <> err
  SeedMissingReference{..} ->
    "Seed: could not resolve " <> entity <> " for " <> show name
  SeedBotRoleMissing -> "Bots: role \"bot\" not found, add it to the seed file."
