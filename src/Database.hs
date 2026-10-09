{-# LANGUAGE RequiredTypeArguments #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Database where

import Control.Monad (void)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Time (getCurrentTime)
import Database.Esqueleto (Entity (..), runMigration)
import Database.Persist (Filter, PersistEntity, PersistEntityBackend, Update, (==.))
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

-- | This function converts id of user from Forgejo library into 'FrId'.
frUser :: FR.UserId -> FrId
frUser (FR.UserId x) = FrId (fromIntegral x)

-- | This function converts id of repository from Forgejo library into 'FrId'.
frRepo :: FR.RepoId -> FrId
frRepo (FR.RepoId x) = FrId (fromIntegral x)

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

{- | Insert a record, or update fields of the entity with the same unique key, in one query.
Unlike 'upsert' it doesn't need existing entity from the caller.
Usage: upsertBy (UniqueUserFrId frId) [UserLogin DB.=. login] user
-}
upsertBy
  :: ( AppState
     , DB.SafeToInsert r
     , MonadIO m
     , PersistEntity r
     , PersistEntityBackend r ~ SqlBackend
     )
  => Unique r
  -> [DB.Update r]
  -> r
  -> m (Key r)
upsertBy u updates record = entityKey <$> withPoolDB (DB.upsertBy u record updates)

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

{- | Update fields of an entity by its key.
Usage: updateById key [UserLogin DB.=. "eshmat"]
-}
updateById
  :: (AppState, MonadIO m, PersistEntity r, PersistEntityBackend r ~ SqlBackend)
  => Key r -> [Update r] -> m ()
updateById k updates = withPoolDB $ DB.update k updates

{- | Update fields of every entity which matches filters.
Usage: updateWhere [PullRequestFilePullRequest DB.==. pr] [PullRequestFileRemovedAt DB.=. Nothing]
-}
updateWhere
  :: (AppState, MonadIO m, PersistEntity r, PersistEntityBackend r ~ SqlBackend)
  => [Filter r] -> [Update r] -> m ()
updateWhere filters updates = withPoolDB $ DB.updateWhere filters updates

{- | Check if any entity matches filters.
Usage: existsWhere [PullRequestEventDeliveryId DB.==. delivery]
-}
existsWhere
  :: (AppState, MonadIO m, PersistEntity r, PersistEntityBackend r ~ SqlBackend)
  => [Filter r] -> m Bool
existsWhere filters = withPoolDB $ DB.exists filters

{- | Delete every entity which matches filters.
Usage: deleteWhere [PullRequestCommitPullRequest DB.==. pr]
-}
deleteWhere
  :: (AppState, MonadIO m, PersistEntity r, PersistEntityBackend r ~ SqlBackend)
  => [Filter r] -> m ()
deleteWhere filters = withPoolDB $ DB.deleteWhere filters

-- FIXME: It will be moved to the dedicated module from Database

-- | Get users with the role. Users without role are never included, so they can't be picked as reviewers.
getByRole :: (AppState, MonadIO m) => RoleId -> m [Entity User]
getByRole role =
  withPoolDB
    $ DB.selectList
      [UserRole ==. Just role]
      []

getByFrId :: (AppState, MonadIO m) => FR.UserId -> m (Maybe (Entity User))
getByFrId uid =
  withPoolDB
    $ DB.selectList [UserFrId ==. frUser uid] []
      >>= pure . listToMaybe

backportExists :: (AppState, MonadIO m) => FrId -> Int -> Text -> m Bool
backportExists repoFrId srcNum target =
  withPoolDB
    $ DB.exists
      [ BackportRecordSourcePrNumber ==. srcNum
      , BackportRecordRepoFrId ==. repoFrId
      , BackportRecordTargetBranch ==. target
      ]

recordBackport :: (AppState, MonadIO m) => FrId -> Int -> Text -> Maybe Int -> BackportStatus -> m ()
recordBackport repoFrId srcNum target backportPrNum status = do
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

backportSucceeded :: (AppState, MonadIO m) => FrId -> Int -> Text -> m Bool
backportSucceeded repoFrId srcNum target =
  withPoolDB $ do
    mrec <- DB.getBy (UniqueBackportRecord srcNum repoFrId target)
    pure $ case mrec of
      Just (Entity _ r) -> backportRecordStatus r == BPOpened
      Nothing -> False

getRepoUsersByRole :: (AppState, MonadIO m) => RoleId -> FrId -> m [Text]
getRepoUsersByRole role repoFrId =
  withPoolDB $ do
    mRepo <- DB.selectFirst [RepositoryFrRepoId ==. repoFrId] []
    case mRepo of
      Nothing -> pure []
      Just (Entity repoKey _) -> do
        contribs <-
          DB.selectList
            [RepoContributorsRepoId ==. repoKey, RepoContributorsRole ==. role]
            []
        users <- traverse (DB.get . (.repoContributorsUserId) . entityVal) contribs
        pure [u.userUsername | Just u <- users]

getUsernamesByRole :: (AppState, MonadIO m) => RoleId -> FrId -> m [Text]
getUsernamesByRole role repoFrId = do
  perRepo <- getRepoUsersByRole role repoFrId
  if not (null perRepo)
    then pure perRepo
    else do
      global <- getByRole role
      pure [(entityVal u).userUsername | u <- global]

getMaintainerUsernames, getContributorUsernames :: (AppState, MonadIO m) => FrId -> m [Text]
getMaintainerUsernames = getUsernamesByRole (toSqlKey 1)
getContributorUsernames = getUsernamesByRole (toSqlKey 2)
