{-# LANGUAGE OverloadedStrings #-}
module Network.TimeoutSpec where

import Test.Hspec
import Control.Concurrent (threadDelay)
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import SpecHelper (
  randomQueueName,
  requestBody,
  createQueue,
  processRequest,
  withConnection
  )

sendReq connection request = do
  createQueue connection (R.queueName request)
  response <- Freddy.deliverWithResponse connection request
  threadDelay (50 * 1000) -- 50 ms to ensure msg has been expired
  return response

spec :: Spec
spec = around withConnection $
  describe "On timeout" $ do
    context "when deleteOnTimeout is set to false" $ do
      let buildRequest queueName = R.newReq {
        R.queueName = queueName,
        R.timeoutInMs = 1,
        R.deleteOnTimeout = False
      }

      it "returns Freddy.TimeoutError" $ \connection -> do
        queueName <- randomQueueName
        let response = sendReq connection $ buildRequest queueName

        response `shouldReturn` Left Freddy.TimeoutError

      it "processes the message after timeout error" $ \connection -> do
        queueName <- randomQueueName
        sendReq connection $ buildRequest queueName

        let gotRequest = processRequest connection queueName
        gotRequest `shouldReturn` True

    context "when deleteOnTimeout is set to true" $ do
      let buildRequest queueName = R.newReq {
        R.queueName = queueName,
        R.timeoutInMs = 1,
        R.deleteOnTimeout = True
      }

      it "returns Freddy.TimeoutError" $ \connection -> do
        queueName <- randomQueueName
        let response = sendReq connection $ buildRequest queueName

        response `shouldReturn` Left Freddy.TimeoutError

      it "does not process the message after timeout" $ \connection -> do
        queueName <- randomQueueName
        sendReq connection $ buildRequest queueName

        let gotRequest = processRequest connection queueName
        gotRequest `shouldReturn` False
