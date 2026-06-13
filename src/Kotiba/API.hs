module Kotiba.API (API, api) where

import Data.Text (Text)
import Servant

type API =
  "health" :> Get '[PlainText] Text

api :: Proxy API
api = Proxy
