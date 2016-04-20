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
  processRequest
  )

spec :: Spec
spec =
  describe "Freddy" $ do
    it "responds to a message" $ do
      connection <- connect
      queueName <- randomQueueName

      Freddy.respondTo connection queueName echoResponder

      let response = Freddy.deliverWithResponse connection R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Right requestBody

    it "returns invalid request error when queue does not exist" $ do
      connection <- connect
      queueName <- randomQueueName

      let response = Freddy.deliverWithResponse connection R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Left Freddy.InvalidRequest

    context "on timeout" $ do
      context "when deleteOnTimeout is set to false" $ do
        it "returns Freddy.TimeoutError" $ do
          connection <- connect
          queueName <- randomQueueName

          createQueue connection queueName

          let response = Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = False
          }

          response `shouldReturn` Left Freddy.TimeoutError

        it "processes the message after timeout error" $ do
          connection <- connect
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
        it "returns Freddy.TimeoutError" $ do
          connection <- connect
          queueName <- randomQueueName

          createQueue connection queueName

          let response = Freddy.deliverWithResponse connection R.newReq {
            R.queueName = queueName,
            R.body = requestBody,
            R.timeoutInMs = 10,
            R.deleteOnTimeout = True
          }

          response `shouldReturn` Left Freddy.TimeoutError

        it "does not process the message after timeout" $ do
          connection <- connect
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
