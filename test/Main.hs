{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import API (runApi)
import Test.Hspec
import Test.Hspec.Wai

main :: IO ()
main = hspec spec

spec :: Spec
spec =
  with (pure app)
    $ describe "GET /health"
    $ it "responds 200 OK"
    $ get "/health" `shouldRespondWith` "1"{matchStatus = 200}
 where
  app = let ?st = error "state is unused by /health" in runApi
