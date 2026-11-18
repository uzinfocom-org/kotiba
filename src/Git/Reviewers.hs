{-# LANGUAGE TypeOperators #-}

module Git.Reviewers where

import Forgejo
import Forgejo.API.PullRequest (PullReviewRequest)
import Forgejo.Methods.PullRequest
import Kotiba.Prelude
import Named
import Servant (Handler)

-- This function requests review from given users and tams on a pull request.
-- It Uses 'addReviewer' method from 'Forgejo' library.
assignReviewers
  :: (AppState)
  => OrgEnv
  -> "owner" :! Text
  -> "repo" :! Text
  -> "index" :! Int
  -> "reviewers" :! [Text]
  -> "teamReviewers" :! [Text]
  -> Handler [PullReviewRequest]
assignReviewers env (Arg owner) (Arg repo) (Arg index) (Arg reviewers) (Arg teamReviewers) =
  withForgejo env
    $ addReviewer
      PullReviewRequestOptions
        { owner
        , repo
        , index
        , reviewers
        , teamReviewers
        }
