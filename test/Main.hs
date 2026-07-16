module Main (main) where

import Kotiba.Server (mkApp)
import Test.Hspec
import Test.Hspec.Wai

main :: IO ()
main = hspec spec

spec :: Spec
spec = with (return mkApp) $ do
    describe "GET /health" $ do
        it "responds 200 OK" $
            get "/health" `shouldRespondWith` "OK"{matchStatus = 200}
