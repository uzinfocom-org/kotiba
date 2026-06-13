{-# LANGUAGE OverloadedStrings #-}

module Kotiba.Server (mkApp, runServer) where

import Data.Text (Text)
import Kotiba.API
import Network.Wai.Handler.Warp (Port, run)
import Servant

mkApp :: Application
mkApp = serve api server

server :: Server API
server = handleHealth 

handleHealth :: Handler Text
handleHealth = return "OK"


runServer :: Port -> IO ()
runServer port = do
  putStrLn $ "Listening on port " <> show port
  run port mkApp
