{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RequiredTypeArguments #-}

module Database.Seed.Bots where

import Config (BotAccount (..))
import Control.Monad (forM_, void)
import Database (getBy, upsert)
import Database.Persist (Entity (..))
import Database.Persist qualified as DB
import Database.Seed.Error (SeedError (..))
import Database.Types
import Kotiba.Prelude

-- | Upsert a single bot account using the resolved role key.
upsertBot :: (AppState, MonadIO m) => RoleId -> BotAccount -> m ()
upsertBot roleKey b = do
  let frId = FrId b.frId
  existing <- getBy (type (Entity User)) (UniqueUserFrId frId)
  void
    $ upsert
      existing
      [ UserLogin DB.=. b.login
      , UserUsername DB.=. b.login
      , UserRole DB.=. Just roleKey
      ]
      User
        { userLogin = b.login
        , userUsername = b.login
        , userFrId = frId
        , userRole = Just roleKey
        }

-- | Synchronize a list of system bot accounts against the "bot" role.
syncBots :: (AppState, MonadIO m, MonadError SeedError m) => [BotAccount] -> m ()
syncBots [] = pure ()
syncBots accounts = do
  Entity roleKey _ <- getBy (type (Entity Role)) (UniqueRoleName "bot") !? SeedBotRoleMissing
  forM_ accounts (upsertBot roleKey)
