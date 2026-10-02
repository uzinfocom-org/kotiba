{-# LANGUAGE OverloadedStrings #-}

module Database.Seed.Bots where

import Config (BotAccount (..))
import Control.Monad (forM_, void)
import Database (getBy, upsert)
import Database.Persist (Entity (..))
import Database.Persist qualified as DB
import Database.Types
import Kotiba.Prelude
import System.IO (hPutStrLn, stderr)

-- | Upsert a single bot account using the resolved role key.
upsertBot :: (AppState, MonadIO m) => RoleId -> BotAccount -> m ()
upsertBot roleKey b = do
  existing <- getBy (type (Entity User)) (UniqueUserFrId b.frId)
  void
    $ upsert
      existing
      [ UserLogin DB.=. b.login
      , UserUsername DB.=. b.login
      , UserRole DB.=. roleKey
      ]
      User{userLogin = b.login, userUsername = b.login, userFrId = b.frId, userRole = roleKey}

-- | Synchronize a list of system bot accounts against the "bot" role.
syncBots :: (AppState, MonadIO m) => [BotAccount] -> m ()
syncBots [] = pure ()
syncBots accounts = do
  mRole <- getBy (type (Entity Role)) (UniqueRoleName "bot")
  maybe handleMissing handleFound mRole
 where
  handleMissing =
    liftIO $ hPutStrLn stderr "Bots: role \"bot\" not found, add it to the seed file."

  handleFound (Entity roleKey _) =
    forM_ accounts (upsertBot roleKey)
