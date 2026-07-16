{-# OPTIONS_GHC -threaded -rtsopts -with-rtsopts=-N #-}

module Main (main) where

import Kotiba.Server (run)

main :: IO ()
main = run
