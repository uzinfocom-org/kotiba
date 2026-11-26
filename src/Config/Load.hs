{-# LANGUAGE OverloadedStrings #-}

{- | Generic TOML loader for barbies-style configs.
Reads the file, puts it over defaults, and reports all missing fields at once.
-}
module Config.Load (ConfigB, emptyConfig, loadConfig) where

import Barbies
import Barbies.Bare
import Control.Applicative ((<|>))
import Data.ByteString qualified as BS
import Data.Either.Validation (Validation, validationToEither)
import Data.Either.Validation qualified as V
import Data.Functor.Compose (Compose (..))
import Data.Functor.Const (Const (..))
import Data.Functor.Identity (Identity (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8)
import GHC.Generics
import System.Exit (die)
import System.IO (hPutStrLn, stderr)
import Toml qualified
import Toml.Schema (FromValue)
import Toml.Schema.Matcher (Result (..))

-- | Just a short name for all the constraints a config record needs.
type ConfigB b =
  ( BareB b
  , TraversableB (b Covered)
  , ApplicativeB (b Covered)
  , FromValue (b Covered Maybe)
  , Generic (b Covered (Const Text))
  , GNames (Rep (b Covered (Const Text)))
  )

{- | Fills every field with its own name. Used for the "missing fields" error,
so names can't go out of sync with the record.
-}
class GNames rep where
  gnames :: rep p

instance (GNames f) => GNames (M1 D d f) where
  gnames = M1 gnames

instance (GNames f) => GNames (M1 C c f) where
  gnames = M1 gnames

instance (GNames f, GNames g) => GNames (f :*: g) where
  gnames = gnames :*: gnames

instance (Selector s) => GNames (M1 S s (K1 i (Const Text a))) where
  gnames = M1 (K1 (Const (T.pack (selName (undefined :: M1 S s (K1 i (Const Text a)) ())))))

emptyConfig :: (ApplicativeB (b Covered)) => b Covered Maybe
emptyConfig = bpure Nothing

-- | First argument wins where it's set.
overlay :: (ApplicativeB (b Covered)) => b Covered Maybe -> b Covered Maybe -> b Covered Maybe
overlay = bzipWith (<|>)

-- | 'Validation' collects the names of all missing fields, not just the first.
require :: Const Text a -> Maybe a -> Compose (Validation [Text]) Identity a
require (Const n) = Compose . maybe (V.Failure [n]) (V.Success . Identity)

finalise :: (ConfigB b) => b Covered Maybe -> Either [Text] (b Bare Identity)
finalise parsed =
  validationToEither
    $ bstrip
      <$> btraverse getCompose (bzipWith require (to gnames) parsed)

-- | Exits with a message if the file is broken or fields are missing.
loadConfig :: (ConfigB b) => b Covered Maybe -> FilePath -> IO (b Bare Identity)
loadConfig defaults filepath = do
  hPutStrLn stderr $ "Loading configuration from: " <> filepath
  decoded <- Toml.decode' . decodeUtf8 <$> BS.readFile filepath
  fromFile <- case decoded of
    Failure errs ->
      die
        $ "Failed to load config "
          <> filepath
          <> ":\n"
          <> unlines (map (("  " <>) . Toml.prettyDecodeError) errs)
    Success _ cfg -> pure cfg
  case finalise (fromFile `overlay` defaults) of
    Left missing ->
      die ("Missing required configuration fields: " <> T.unpack (T.intercalate ", " missing))
    Right cfg -> pure cfg
