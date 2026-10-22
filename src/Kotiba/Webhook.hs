{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}

module Kotiba.Webhook where

import Control.Monad (unless)
import Control.Monad.IO.Class (liftIO)
import Crypto.Hash (Digest, SHA256, digestFromByteString)
import Crypto.MAC.HMAC (HMAC (..), hmac)
import Data.Aeson (FromJSON, eitherDecode)
import Data.ByteArray.Encoding qualified as BAE
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BSL
import Data.ByteString.Lazy.Char8 qualified as BSLC
import Data.Foldable (for_)
import Data.Maybe (fromMaybe)
import Network.Wai (requestHeaders, strictRequestBody)
import Servant
import Servant.Server.Internal.Delayed (addBodyCheck)
import Servant.Server.Internal.DelayedIO (DelayedIO, delayedFailFatal, withRequest)

-- | Like @ReqBody '[JSON] a@, but checks HMAC signature first and decodes JSON after.
data SignedBody a

-- | Lives in servant 'Context', found by type. @Nothing@ means no verification.
newtype WebhookSecret = WebhookSecret (Maybe BS.ByteString)

instance
  (FromJSON a, HasServer api ctx, HasContextEntry ctx WebhookSecret)
  => HasServer (SignedBody a :> api) ctx
  where
  -- handler takes the decoded body, then the rest
  type ServerT (SignedBody a :> api) m = a -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  -- runs once on startup, only builds the recipe
  route _ ctx sub = route (Proxy @api) ctx (addBodyCheck sub (pure ()) check)
   where
    WebhookSecret msecret = getContextEntry ctx

    -- runs on every request, in body stage
    check :: () -> DelayedIO a
    check () = withRequest $ \req -> do
      -- body can be read only once and HMAC needs exact bytes, so keep raw
      raw <- liftIO $ strictRequestBody req
      let headers = requestHeaders req
      let sig = lookup "x-forgejo-signature" headers
          sigInvalid = err401{errBody = "Invalid X-Forgejo-Signature"}

      for_ msecret $ \secret ->
        unless (validSignature secret sig raw) $
          delayedFailFatal sigInvalid

      -- parse only after signature is fine
      either (\e -> delayedFailFatal err400{errBody = BSLC.pack e}) pure $ eitherDecode raw

    validSignature :: BS.ByteString -> Maybe BS.ByteString -> BSL.ByteString -> Bool
    validSignature secret mSig raw = fromMaybe False $ do
      hex <- mSig
      bytes <- either (const Nothing) Just (BAE.convertFromBase BAE.Base16 hex :: Either String BS.ByteString)
      d <- digestFromByteString bytes

      pure (hmac secret (BSL.toStrict raw) == HMAC (d :: Digest SHA256))
