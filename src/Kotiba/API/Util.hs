{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Kotiba.API.Util where

import Control.Monad.Except (ExceptT (..), MonadError (..))
import Control.Monad.Trans (MonadTrans (..))
import Control.Monad.Trans.Except (runExceptT)
import Kotiba.Prelude
import Network.HTTP.Media qualified as HTTPMedia
import Network.HTTP.Types qualified as HTTP
import Servant

----------------------- Error formatting ------------------

errorFormatters :: Context '[ErrorFormatters]
errorFormatters = (customFormatters :. EmptyContext)

customFormatters :: ErrorFormatters
customFormatters =
  defaultErrorFormatters
    { -- bodyParserErrorFormatter = bodyParserErrorFormatter'
      bodyParserErrorFormatter = bodyParserErrorFormatter'
    }

bodyParserErrorFormatter' :: ErrorFormatter
bodyParserErrorFormatter' _ _ errMsg =
  ServerError
    { errHTTPCode = HTTP.statusCode HTTP.status400
    , -- , errReasonPhrase = UTF8.toString $ HTTP.statusMessage HTTP.status400
      -- , errBody =
      --     AS.encode $
      --       AS.object
      --         [ "code" AS..= AS.Number 400
      --         , "message" AS..= errMsg -- FIXME: need implement error scope for example: { ... "scope": "ReqBody"}
      --         ]
      errHeaders = [(HTTP.hContentType, HTTPMedia.renderHeader (Servant.contentType (Proxy @Servant.JSON)))]
    }

----------------------- Throwing api errors ------------------
type UVerbT :: [Type] -> (Type -> Type) -> Type -> Type
newtype UVerbT xs m a = UVerbT {unUVerbT :: ExceptT (Union xs) m a}
  deriving newtype (Applicative, Functor, Monad, MonadIO, MonadTrans)

instance (MonadError e m) => MonadError e (UVerbT xs m) where
  throwError = lift . throwError
  catchError (UVerbT act) h =
    UVerbT
      $ ExceptT
      $ runExceptT act `catchError` (runExceptT . unUVerbT . h)

{- | This combinator runs 'UVerbT'. It applies 'respond' internally, so the handler
may use the usual 'return'.
-}
runUVerbT :: (HasStatus x, IsMember x xs, Monad m) => UVerbT xs m x -> m (Union xs)
runUVerbT (UVerbT act) = either id id <$> runExceptT (act >>= respond)

-- | Short-circuit 'UVerbT' computation returning one of the response types.
throwUVerb :: (HasStatus x, IsMember x xs, Monad m) => x -> UVerbT xs m a
throwUVerb = UVerbT . ExceptT . fmap Left . respond

-------------------------- Prelude for http responses --------------------------

type ResponseError :: Type -> Type
data ResponseError a = MKResponseError {error :: a}
  deriving (Eq, Generic, Show)

type BadRequest :: Type
data BadRequest = MkBadRequest {message :: Text}
  deriving (Eq, Generic, Show)

deriving anyclass instance ToJSON BadRequest
deriving anyclass instance FromJSON BadRequest

-- deriving anyclass instance ToSchema BadRequest
-- instance HasStatus BadRequest where
--   type StatusOf BadRequest = 400

-- | This combinator runs 'throwUVerb' and respond BadRequest with 400 status code
throwBadRequest = undefined -- TODO: Need implement

-- | This combinator runs 'return' with response and status code 201
respond201 :: (Monad m) => a -> m (WithStatus 201 a)
respond201 a = do return $ WithStatus @201 a
