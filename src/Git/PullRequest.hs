{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}

module Git.PullRequest where

import Forgejo
import Forgejo.API.PullRequest (PullReviewRequest)
import Forgejo.Methods.PullRequest
import Kotiba.Prelude
import Named
import Servant (Handler)

assignReviewers
  :: (AppState)
  => "owner" :! Text
  -> "repo" :! Text
  -> "index" :! Int
  -> "reviewers" :! [Text]
  -> "teamReviewers" :! [Text]
  -> Handler [PullReviewRequest]
assignReviewers (Arg owner) (Arg repo) (Arg index) (Arg reviewers) (Arg teamReviewers) =
  withForgejo
    $ addReviewer
      PullReviewRequestOptions
        { owner
        , repo
        , index
        , reviewers
        , teamReviewers
        }
