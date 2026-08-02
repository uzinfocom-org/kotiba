{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module API.Dev where

import Database qualified as DB
import Database.Esqueleto (Entity (..))
import Database.Types
import Kotiba.Prelude
import Servant
import Servant.Server.Generic (AsServer)

data Resp = Resp
  { res :: Int
  }
  deriving stock (Generic, Show)
  deriving anyclass (FromJSON, ToJSON)

-- Routes
type DevRoutes :: Type -> Type
data DevRoutes route = MkDevRoutes
  { _createRole :: route :- "roles" :> ReqBody '[JSON] Role :> Post '[JSON] (RoleView)
  , _createUser :: route :- "users" :> ReqBody '[JSON] User :> Post '[JSON] (UserView)
  }
  deriving stock (Generic)

createRole :: (AppState) => Role -> Handler (RoleView)
createRole r = do
  rr <- DB.create (type (Entity Role)) r
  pure $ entityToRoleView rr

createUser :: (AppState) => User -> Handler (UserView)
createUser u = do
  rr <- DB.create (type (Entity User)) u
  pure $ entityToUserView rr

---------------------------------------------------------------
--- Handlers
---------------------------------------------------------------

devHandlers :: (AppState) => DevRoutes AsServer
devHandlers = MkDevRoutes{_createRole = createRole, _createUser = createUser}
