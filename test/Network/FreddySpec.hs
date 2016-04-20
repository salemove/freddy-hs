{-# LANGUAGE OverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import System.Random (randomIO)
import Data.UUID (UUID, toText)
import Data.Text (Text)
import Control.Concurrent (threadDelay, newEmptyMVar, takeMVar)
import System.Timeout (timeout)
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import SpecHelper (
  newUUID,
  randomQueueName,
  echoResponder,
  delayedResponder,
  connect,
  requestBody,
  createQueue,
  processRequest,
  withConnection
  )

spec :: Spec
spec = around withConnection $
  describe "Freddy" $ do
    it "responds to a message" $ \connection -> do
      queueName <- randomQueueName

      Freddy.respondTo connection queueName echoResponder

      let response = Freddy.deliverWithResponse connection R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Right requestBody

    it "returns invalid request error when queue does not exist" $ \connection -> do
      queueName <- randomQueueName

      let response = Freddy.deliverWithResponse connection R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Left Freddy.InvalidRequest

    context "on timeout" $ do
      context "when deleteOnTimeout is set to false" $ do
        it "returns Freddy.TimeoutError" $ \connection -> do
          queueName <- randomQueueName

          createQueue connection queueName

          let response = Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = False
          }

          response `shouldReturn` Left Freddy.TimeoutError

        it "processes the message after timeout error" $ \connection -> do
          queueName <- randomQueueName

          createQueue connection queueName

          Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = False
          }

          let gotRequest = processRequest connection queueName

          gotRequest `shouldReturn` True

      context "when deleteOnTimeout is set to true" $ do
        it "returns Freddy.TimeoutError" $ \connection -> do
          queueName <- randomQueueName

          createQueue connection queueName

          let response = Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = True
          }

          response `shouldReturn` Left Freddy.TimeoutError

        it "does not process the message after timeout" $ \connection -> do
          queueName <- randomQueueName

          createQueue connection queueName

          Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = True
          }

          let gotRequest = processRequest connection queueName

          gotRequest `shouldReturn` False
