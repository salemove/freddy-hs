{-# LANGUAGE OverloadedStrings #-}
module Network.TimeoutSpec where

import Test.Hspec
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import SpecHelper (
  randomQueueName,
  requestBody,
  createQueue,
  processRequest,
  withConnection
  )

spec :: Spec
spec = around withConnection $
  describe "On timeout" $ do
    context "when deleteOnTimeout is set to false" $ do
      let buildRequest queueName = R.newReq {
        R.queueName = queueName,
        R.body = requestBody,
        R.timeoutInMs = 10,
        R.deleteOnTimeout = False
      }

      it "returns Freddy.TimeoutError" $ \connection -> do
        queueName <- randomQueueName

        createQueue connection queueName

        let response = Freddy.deliverWithResponse connection $ buildRequest queueName

        response `shouldReturn` Left Freddy.TimeoutError

      it "processes the message after timeout error" $ \connection -> do
        queueName <- randomQueueName

        createQueue connection queueName

        Freddy.deliverWithResponse connection $ buildRequest queueName

        let gotRequest = processRequest connection queueName

        gotRequest `shouldReturn` True

    context "when deleteOnTimeout is set to true" $ do
      let buildRequest queueName = R.newReq {
        R.queueName = queueName,
        R.body = requestBody,
        R.timeoutInMs = 10,
        R.deleteOnTimeout = True
      }

      it "returns Freddy.TimeoutError" $ \connection -> do
        queueName <- randomQueueName

        createQueue connection queueName

        let response = Freddy.deliverWithResponse connection $ buildRequest queueName

        response `shouldReturn` Left Freddy.TimeoutError

      it "does not process the message after timeout" $ \connection -> do
        queueName <- randomQueueName

        createQueue connection queueName

        Freddy.deliverWithResponse connection $ buildRequest queueName

        let gotRequest = processRequest connection queueName

        gotRequest `shouldReturn` False
