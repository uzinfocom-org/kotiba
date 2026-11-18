{-# LANGUAGE OverloadedLabels #-}

module Events.PullRequest (processPrOpen) where

import Data.List ((!?))
import Data.Maybe (maybeToList)
import Database qualified as DB
import Forgejo
import Forgejo.API.PullRequest (PullReviewRequest)
import Git.Reviewers (assignReviewers)
import Kotiba.Prelude hiding ((!?))
import Named
import Servant (Handler)
import System.Random (randomRIO)

processPrOpen :: (AppState) => OrgEnv -> PullRequestPayload -> Handler [PullReviewRequest]
processPrOpen = processReviewers

-- FIXME: We'll move helper functions to independent like Prelude in future
pickRandom :: (MonadIO m) => [a] -> m (Maybe a)
pickRandom [] = pure Nothing
pickRandom xs = (xs !?) <$> randomRIO (0, length xs - 1)

processReviewers :: (AppState) => OrgEnv -> PullRequestPayload -> Handler [PullReviewRequest]
processReviewers env PullRequestPayload{..} = do
  maintainerNames <- DB.getMaintainerUsernames repoFrId
  contributorNames <- DB.getContributorUsernames repoFrId
  luckyContributor <- maybeToList <$> pickRandom contributorNames

  let reviewers = maintainerNames <> luckyContributor
      usernames = excluding author reviewers

  assignReviewers env
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
  repoFrId = DB.frRepo prpRepository.repoId
