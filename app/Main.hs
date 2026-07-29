{-# OPTIONS_GHC -threaded -rtsopts -with-rtsopts=-N #-}

module Main (main) where

import Server (run)

main :: IO ()
main = run
