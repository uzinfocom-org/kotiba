module Git.Release
  ( generateReleaseNotes
  , RnaError (..)
  ) where

import Control.Exception.Safe (SomeException, try)
import Data.Text qualified as T
import Kotiba.Prelude
import Servant (Handler)
import System.Process.Typed (ExitCode (..), proc, runProcess)

data RnaError
  = RnaProcessError Int Text
  | RnaException Text
  deriving stock (Eq, Show)

generateReleaseNotes
  :: (AppState)
  => Text -- Owner
  -> Text -- Repo
  -> Text -- Tag
  -> Handler (Either RnaError ())
generateReleaseNotes owner repo tag = do
  let forgejoUrl = T.unpack ?st.config.forgejoUrl
      token = T.unpack ?st.config.forgejoToken
      repoArg = T.unpack $ owner <> T.pack "/" <> repo
      tagArg = T.unpack tag
      args =
        [ "--forgejo-url"
        , forgejoUrl
        , "--repository"
        , repoArg
        , "--token"
        , token
        , "--tag"
        , tagArg
        ]

  result <- liftIO . try . runProcess $ proc "release-notes-assistant" args
  pure case result of
    Left (err :: SomeException) -> Left . RnaException . T.pack $ show err
    Right ExitSuccess -> Right ()
    Right (ExitFailure code) -> Left . RnaProcessError code $ T.pack "RNA subprocess failed"
