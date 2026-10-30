{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Kotiba.Webhook where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Crypto.Hash (SHA256, digestFromByteString)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.Aeson (FromJSON, eitherDecode)
-- import Data.ByteArray (constEq)
import Data.ByteArray.Encoding qualified as BAE
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.Text qualified as T
import Data.Text.Encoding (encodeUtf8)
import Network.HTTP.Types (RequestHeaders)
import Network.Wai (requestHeaders, strictRequestBody)
import Servant
import Servant.Server.Internal.Delayed (addBodyCheck)
import Servant.Server.Internal.DelayedIO (DelayedIO, delayedFailFatal, withRequest)

-- | Like @ReqBody '[JSON] a@, but checks HMAC signature first and decodes JSON after.
data SignedBody a

-- | Lives in servant 'Context', found by type. 'Unsigned' means no verification.
data WebhookSecret = Unsigned | Signed BS.ByteString

data SigError = MissingSig | MalformedSig | BadSig
  deriving (Eq, Show)

sigErr :: SigError -> ServerError
sigErr MissingSig = err401{errBody = "Missing X-Forgejo-Signature"}
sigErr MalformedSig = err400{errBody = "Malformed X-Forgejo-Signature"}
sigErr BadSig = err401{errBody = "Invalid X-Forgejo-Signature"}

verifySignature :: WebhookSecret -> RequestHeaders -> BSL.ByteString -> Either SigError ()
verifySignature Unsigned _ _ = Right ()
verifySignature (Signed key) hs body = do
  hex <- maybe (Left MissingSig) Right (lookup "X-Forgejo-Signature" hs)
  sig <- either (const $ Left MalformedSig) Right (BAE.convertFromBase BAE.Base16 hex :: Either String BS.ByteString)
  given <- maybe (Left BadSig) Right (digestFromByteString sig)
  unless (given == hmacGetDigest (mac key)) $ Left BadSig
 where
  mac :: BS.ByteString -> HMAC SHA256
  mac k = hmac k (BSL.toStrict body)

instance
  (FromJSON a, HasContextEntry ctx WebhookSecret, HasServer api ctx)
  => HasServer (SignedBody a :> api) ctx
  where
  -- handler takes the decoded body, then the rest
  type ServerT (SignedBody a :> api) m = a -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  -- runs once on startup, only builds the recipe
  route _ ctx sub = route (Proxy @api) ctx (addBodyCheck sub (pure ()) (const check))
   where
    -- runs on every request, in body stage
    check :: DelayedIO a
    check = do
      let secret = getContextEntry ctx
      req <- withRequest pure
      body <- liftIO $ strictRequestBody req
      orFail sigErr $ verifySignature secret (requestHeaders req) body
      orFail decodeErr $ eitherDecode body

decodeErr :: String -> ServerError
decodeErr e = err400{errBody = "Bad JSON: " <> BSL.fromStrict (encodeUtf8 $ T.pack e)}

orFail :: (e -> ServerError) -> Either e a -> DelayedIO a
orFail toErr = either (delayedFailFatal . toErr) pure
