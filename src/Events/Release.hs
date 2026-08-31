module Events.Release
  ( processRelease
  ) where

import Forgejo
import Forgejo.Types.Release (ReleasePayload (..))
import Kotiba.Prelude
import Servant (Handler)

processRelease :: ReleasePayload -> Handler ()
processRelease _ = pure ()
