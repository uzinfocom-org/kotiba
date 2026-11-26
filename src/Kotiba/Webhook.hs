{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

-- | Auth for incoming webhooks. The Forgejo lib only parses payloads, checking is done here.
module Kotiba.Webhook where

import Control.Monad (unless)
import Crypto.Hash (SHA256, digestFromByteString)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.Aeson (Value, eitherDecode, withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteArray.Encoding qualified as BAE
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Forgejo (Delivery, ForgejoEvent, ForgejoEventType, WebhookPayload, webhookHandlerWith)
import Kotiba.Prelude
import Network.HTTP.Types (RequestHeaders)
import Network.Wai (requestHeaders, strictRequestBody)
import Servant
import Servant.Server.Internal.Delayed (addBodyCheck)
import Servant.Server.Internal.DelayedIO (DelayedIO, delayedFailFatal, withRequest)

{- | Like @ReqBody '[JSON] a@, but it checks the signature first.
The org comes from the payload, and its secret is the one used for the check.
-}
data SignedBody

data Verified = Verified
  { org :: OrgEnv
  , payload :: Value
  }

-- | Lives in servant 'Context'. Finds an org by name, ignoring case.
newtype OrgLookup = OrgLookup (Text -> Maybe OrgEnv)

{- | Not verified yet, it's only a key to find the secret.
If someone fakes the name, they can't sign for it anyway.
-}
ownerLogin :: Value -> Parser Text
ownerLogin = withObject "payload" \o -> do
  repo <- o .: "repository"
  owner <- repo .: "owner"
  T.toLower <$> owner .: "login"

data SigError = MissingSig | MalformedSig | BadSig
  deriving (Eq, Show)

sigErr :: SigError -> ServerError
sigErr MissingSig = err401{errBody = "Missing X-Forgejo-Signature"}
sigErr MalformedSig = err400{errBody = "Malformed X-Forgejo-Signature"}
sigErr BadSig = err401{errBody = "Invalid X-Forgejo-Signature"}

unknownOrg :: ServerError
unknownOrg = err401{errBody = "Unknown organization"}

-- | Header is hex of HMAC-SHA256 over the raw body.
verifySignature :: BS.ByteString -> RequestHeaders -> BSL.ByteString -> Either SigError ()
verifySignature key hs body = do
  hex <- maybe (Left MissingSig) Right (lookup "X-Forgejo-Signature" hs)
  sig <- either (const $ Left MalformedSig) Right (BAE.convertFromBase BAE.Base16 hex :: Either String BS.ByteString)
  given <- maybe (Left BadSig) Right (digestFromByteString sig)
  unless (given == hmacGetDigest mac) $ Left BadSig
 where
  mac :: HMAC SHA256
  mac = hmac key (BSL.toStrict body)

instance
  (HasContextEntry ctx OrgLookup, HasServer api ctx)
  => HasServer (SignedBody :> api) ctx
  where
  -- handler gets the verified delivery, then the rest
  type ServerT (SignedBody :> api) m = Verified -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  -- runs once at startup, only builds the recipe
  route _ ctx sub = route (Proxy @api) ctx (addBodyCheck sub (pure ()) (const check))
   where
    -- runs on every request
    check :: DelayedIO Verified
    check = do
      let OrgLookup find = getContextEntry ctx
      req <- withRequest pure
      body <- liftIO $ strictRequestBody req
      v <- orFail decodeErr $ eitherDecode @Value body
      orgKey <- orFail decodeErr $ parseEither ownerLogin v
      env <- orFail (const unknownOrg) $ maybe (Left ()) Right (find orgKey)
      orFail sigErr $ verifySignature env.orgWebhookSecret (requestHeaders req) body
      pure Verified{org = env, payload = v}

-- | Binds @?org@ for the callback, the lib does the parsing.
onWebhook
  :: ((OrgState) => Delivery -> WebhookPayload -> Handler ())
  -> Maybe (Either Text ForgejoEvent)
  -> Maybe (Either Text ForgejoEventType)
  -> Maybe Text
  -> Verified
  -> Handler ()
onWebhook cb ev evTy did (Verified env v) =
  webhookHandlerWith (\d p -> let ?org = env in cb d p) ev evTy did v

decodeErr :: String -> ServerError
decodeErr e = err400{errBody = "Bad JSON: " <> BSL.fromStrict (encodeUtf8 $ T.pack e)}

-- | Fatal, so servant doesn't try other routes.
orFail :: (e -> ServerError) -> Either e a -> DelayedIO a
orFail toErr = either (delayedFailFatal . toErr) pure
