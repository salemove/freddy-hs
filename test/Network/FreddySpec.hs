{-# LANGUAGE OverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import SpecHelper (
  randomQueueName,
  echoResponder,
  requestBody,
  withConnection
  )

spec :: Spec
spec = around withConnection $
  describe "Freddy" $ do
    let buildRequest queueName = R.newReq {
      R.queueName = queueName,
      R.body = requestBody
    }

    it "responds to a message" $ \connection -> do
      queueName <- randomQueueName

      Freddy.respondTo connection queueName echoResponder

      let response = Freddy.deliverWithResponse connection (buildRequest queueName)

      response `shouldReturn` Right requestBody

    it "returns invalid request error when queue does not exist" $ \connection -> do
      queueName <- randomQueueName

      let response = Freddy.deliverWithResponse connection (buildRequest queueName)

      response `shouldReturn` Left Freddy.InvalidRequest

