{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Kotiba.Webhook where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Crypto.Hash (SHA256)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.Aeson (FromJSON, eitherDecode)
import Data.ByteArray (constEq)
import Data.ByteArray.Encoding qualified as BAE
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Lazy.Char8 qualified as BSLC
import Network.Wai (requestHeaders, strictRequestBody)
import Servant
import Servant.Server.Internal.Delayed (addBodyCheck)
import Servant.Server.Internal.DelayedIO (DelayedIO, delayedFail, withRequest)

-- | Like @ReqBody '[JSON] a@, but checks HMAC signature first and decodes JSON after.
data SignedBody a

-- | Lives in servant 'Context', found by type. 'Unsigned' means no verification.
data WebhookSecret = Unsigned | Signed BS.ByteString

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
    secret :: WebhookSecret
    secret = getContextEntry ctx

    sigInvalid = err401{errBody = "Invalid X-Forgejo-Signature"}

    -- runs on every request, in body stage
    check :: DelayedIO a
    check = withRequest $ \req -> do
      -- body can be read only once and HMAC needs exact bytes, so keep raw
      raw <- liftIO $ strictRequestBody req

      case secret of
        Unsigned -> pure ()
        Signed key ->
          unless (maybe False (validSignature key raw) (lookup "x-forgejo-signature" (requestHeaders req)))
            $ delayedFail sigInvalid

      -- parse only after signature is fine
      either (\e -> delayedFail err400{errBody = BSLC.pack e}) pure $ eitherDecode raw

    validSignature :: BS.ByteString -> BSL.ByteString -> BS.ByteString -> Bool
    validSignature key raw sigHex =
      expected `constEq` sigHex
     where
      expected :: BS.ByteString
      expected = BAE.convertToBase BAE.Base16 (hmacGetDigest mac)

      mac :: HMAC SHA256
      mac = hmac key (BSL.toStrict raw)
