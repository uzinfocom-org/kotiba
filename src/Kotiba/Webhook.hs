{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

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

data SignedBody a

newtype WebhookSecret = WebhookSecret (Maybe BS.ByteString)

instance
  (FromJSON a, HasServer api ctx, HasContextEntry ctx WebhookSecret)
  => HasServer (SignedBody a :> api) ctx
  where
  type ServerT (SignedBody a :> api) m = a -> ServerT api m

  hoistServerWithContext _ pc nt s = hoistServerWithContext (Proxy @api) pc nt . s

  route _ ctx sub = route (Proxy @api) ctx (addBodyCheck sub (pure ()) check)
   where
    WebhookSecret msecret = getContextEntry ctx

    check :: () -> DelayedIO a
    check () = withRequest $ \req -> do
      raw <- liftIO $ strictRequestBody req
      for_ msecret $ \secret ->
        unless (validSignature secret (lookup "x-forgejo-signature" $ requestHeaders req) raw) $
          delayedFailFatal err401{errBody = "Invalid X-Forgejo-Signature"}
      either (\e -> delayedFailFatal err400{errBody = BSLC.pack e}) pure $ eitherDecode raw

validSignature :: BS.ByteString -> Maybe BS.ByteString -> BSL.ByteString -> Bool
validSignature secret mSig raw = fromMaybe False $ do
  hex <- mSig
  bytes <- either (const Nothing) Just (BAE.convertFromBase BAE.Base16 hex :: Either String BS.ByteString)
  d <- digestFromByteString bytes
  pure (hmac secret (BSL.toStrict raw) == HMAC (d :: Digest SHA256))
