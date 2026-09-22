{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE TypeOperators #-}

module Events.PullRequest (processPrOpen) where

import Data.List ((!?))
import Data.Maybe (maybeToList)
import Database qualified as DB
import Database.Esqueleto (Entity (..), toSqlKey)
import Database.Types qualified as DB
import Forgejo.Types.Common (RepoId (..))
import Forgejo
import Forgejo.API.PullRequest (PullReviewRequest)
import Git.PullRequest (assignReviewers)
import Kotiba.Prelude
import Named
import Servant (Handler)
import System.Random (randomRIO)

processPrOpen :: (AppState) => PullRequestPayload -> Handler [PullReviewRequest]
processPrOpen PullRequestPayload{..} = do
  maintainerNames <- DB.getMaintainerUsernames repoFrId
  contributorNames <- DB.getContributorUsernames repoFrId
  luckyContributor <- maybeToList <$> pickRandom contributorNames

  let reviewers = maintainerNames <> luckyContributor
      usernames = excluding author reviewers

  assignReviewers
    ! #owner orgName
    ! #repo repoName
    ! #index index
    ! #reviewers usernames
    ! #teamReviewers []
 where
  excluding username = filter (/= username)
  author = prpSender.userUsername
  orgName = prpRepository.repoOwner.userLogin
  repoName = prpRepository.repoName
  index = prpPullRequest.prNumber
  repoFrId = case prpRepository.repoId of RepoId rid -> fromIntegral rid

-- FIXME: We'll move helper functions to independent like Prelude in future
pickRandom :: (MonadIO m) => [a] -> m (Maybe a)
pickRandom [] = pure Nothing
pickRandom xs = (xs !?) <$> randomRIO (0, length xs - 1)
