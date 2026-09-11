{-# LANGUAGE RequiredTypeArguments #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Database where

import Control.Monad (void)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time (getCurrentTime)
import Database.Esqueleto (Entity (..), runMigration)
import Database.Persist (PersistEntity, PersistEntityBackend, (==.))
import Database.Persist qualified as DB
import Database.Persist.Sql (SqlBackend, SqlPersistT, runSqlPool, toSqlKey)
import Database.Types
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

{- | Get an entity by a unique constraint.
Usage: getBy (type (Entity User)) (UniqueUsername "eshmat")
-}
getBy
  :: forall e
    ->( AppState
      , MonadIO m
      , PersistEntity (RecordOf e)
      , PersistEntityBackend (RecordOf e) ~ SqlBackend
      , e ~ Entity (RecordOf e)
      )
  => Unique (RecordOf e)
  -> m (Maybe e)
getBy _ u = withPoolDB $ DB.getBy u

{- | Insert a record or update it if a matching entity already exists.
Usage: upsert existing updates record
-}
upsert
  :: ( AppState
     , DB.SafeToInsert r
     , MonadIO m
     , PersistEntity r
     , PersistEntityBackend r ~ SqlBackend
     )
  => Maybe (Entity r)
  -> [DB.Update r]
  -> r
  -> m (Key r)
upsert existing updates record =
  fromMaybe (withPoolDB $ DB.insert record)
    $ (\(Entity k _) -> k <$ withPoolDB (DB.update k updates)) <$> existing

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

backportExists :: (AppState, MonadIO m) => Int -> Int -> Text -> m Bool
backportExists srcNum repoFrId target =
  withPoolDB
    $ DB.exists
      [ BackportRecordSourcePrNumber ==. srcNum
      , BackportRecordRepoFrId ==. repoFrId
      , BackportRecordTargetBranch ==. target
      ]

recordBackport :: (AppState, MonadIO m) => Int -> Int -> Text -> Maybe Int -> BackportStatus -> m ()
recordBackport srcNum repoFrId target backportPrNum status = do
  now <- liftIO getCurrentTime
  withPoolDB $ do
    existing <- DB.getBy (UniqueBackportRecord srcNum repoFrId target)
    case existing of
      Just (Entity key _) ->
        DB.update
          key
          [ BackportRecordStatus DB.=. status
          , BackportRecordBackportPrNumber DB.=. backportPrNum
          , BackportRecordCreatedAt DB.=. now
          ]
      Nothing ->
        void
          $ DB.insert
            BackportRecord
              { backportRecordSourcePrNumber = srcNum
              , backportRecordRepoFrId = repoFrId
              , backportRecordTargetBranch = target
              , backportRecordBackportPrNumber = backportPrNum
              , backportRecordStatus = status
              , backportRecordCreatedAt = now
              }

backportSucceeded :: (AppState, MonadIO m) => Int -> Int -> Text -> m Bool
backportSucceeded srcNum repoFrId target =
  withPoolDB $ do
    mrec <- DB.getBy (UniqueBackportRecord srcNum repoFrId target)
    pure $ case mrec of
      Just (Entity _ r) -> backportRecordStatus r == BPOpened
      Nothing -> False

getRepoMaintainers :: (AppState, MonadIO m) => Int -> m [Text]
getRepoMaintainers repoFrId =
  withPoolDB $ do
    mRepo <- DB.selectFirst [RepositoryFrRepoId ==. repoFrId] []
    case mRepo of
      Nothing -> pure []
      Just (Entity repoKey _) -> do
        contribs <-
          DB.selectList
            [RepoContributorsRepoId ==. repoKey, RepoContributorsRole ==. toSqlKey 1]
            []
        users <- traverse (DB.get . (.repoContributorsUserId) . entityVal) contribs
        pure [u.userUsername | Just u <- users]

getMaintainerUsernames :: (AppState, MonadIO m) => Int -> m [Text]
getMaintainerUsernames repoFrId = do
  perRepo <- getRepoMaintainers repoFrId
  if not (null perRepo)
    then pure perRepo
    else do
      global <- getByRole (toSqlKey 1)
      pure [(entityVal u).userUsername | u <- global]
