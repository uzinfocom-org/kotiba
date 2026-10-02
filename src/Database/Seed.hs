{-# LANGUAGE OverloadedStrings #-}

module Database.Seed
  ( syncBots, seedIfChanged
  ) where

import Database.Seed.Bots (syncBots)
import Database.Seed.Runner (seedIfChanged)
