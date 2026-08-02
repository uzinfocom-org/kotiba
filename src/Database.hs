{-# LANGUAGE RequiredTypeArguments #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Database where

import Data.Maybe (listToMaybe)
import Database.Esqueleto (Entity, runMigration)
import Database.Persist (Key, PersistEntity, PersistEntityBackend, (==.))
import Database.Persist qualified as DB
import Database.Persist.Sql (SqlBackend, SqlPersistT, runSqlPool)
import Database.Types (EntityField (UserFrId, UserRole), RoleId, User, migrateAll)
import Forgejo.Types.Common qualified as FR
import Kotiba.Prelude

withPoolDB :: (AppState, MonadIO m) => SqlPersistT IO a -> m a
withPoolDB q = liftIO $ runSqlPool q ?st.db

migrateDB' :: (AppState) => IO ()
migrateDB' = withPoolDB $ runMigration migrateAll

type family RecordOf e where
  RecordOf (Entity r) = r

{- | Get an entity by its key.
Usage: getById (type (Entity User)) userId
-}
getById
  :: forall e
    ->( AppState
      , MonadIO m
      , PersistEntity (RecordOf e)
      , PersistEntityBackend (RecordOf e) ~ SqlBackend
      , e ~ Entity (RecordOf e)
      )
  => Key (RecordOf e)
  -> m (Maybe e)
getById _ i = withPoolDB $ DB.getEntity i

{- | Insert a new record and return its key.
Usage: create (type (Entity User)) userRecord
-}
create
  :: forall e
    ->( AppState
      , DB.SafeToInsert (RecordOf e)
      , MonadIO m
      , PersistEntity (RecordOf e)
      , PersistEntityBackend (RecordOf e) ~ SqlBackend
      , e ~ Entity (RecordOf e)
      )
  => RecordOf e -> m e
create _ r = withPoolDB $ DB.insertEntity r

{- | Insert a new record and return its key.
Usage: create (type (Entity User)) userRecord
-}
createKey
  :: forall e
    ->( AppState
      , DB.SafeToInsert (RecordOf e)
      , MonadIO m
      , PersistEntity (RecordOf e)
      , PersistEntityBackend (RecordOf e) ~ SqlBackend
      , e ~ Entity (RecordOf e)
      )
  => RecordOf e -> m (Key (RecordOf e))
createKey _ r = withPoolDB $ DB.insert r

{- | Get all entities of a type.
Usage: getAll (type (Entity User))
-}
getAll
  :: forall e
    ->( AppState
      , MonadIO m
      , PersistEntity (RecordOf e)
      , PersistEntityBackend (RecordOf e) ~ SqlBackend
      , e ~ Entity (RecordOf e)
      )
  => m [e]
getAll _ = withPoolDB $ DB.selectList [] []

-- FIXME: It will be moved to the dedicated module from Database
getByRole :: (AppState, MonadIO m) => RoleId -> m [Entity User]
getByRole role =
  withPoolDB
    $ DB.selectList
      [UserRole ==. role]
      []

getByFrId :: (AppState, MonadIO m) => FR.UserId -> m (Maybe (Entity User))
getByFrId (FR.UserId x) =
  withPoolDB
    $ DB.selectList [UserFrId ==. (fromIntegral x)] []
      >>= pure . listToMaybe
