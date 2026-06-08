module Kotiba.Api (API, api) where

import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Servant

type API =
  "health" :> Get '[PlainText] Text

api :: Proxy API
api = Proxy
