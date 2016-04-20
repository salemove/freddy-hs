{-# LANGUAGE OverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import System.Random (randomIO)
import Data.UUID (UUID, toText)
import Data.Text (Text)
import Control.Concurrent (threadDelay)
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import SpecHelper (
  newUUID,
  randomQueueName,
  echoResponder,
  delayedResponder,
  connect,
  requestBody
  )

spec :: Spec
spec =
  describe "Freddy" $ do
    it "can respond to messages" $ do
      (respondTo, deliverWithResponse) <- connect
      queueName <- randomQueueName

      respondTo queueName echoResponder

      let response = deliverWithResponse R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Right requestBody

    it "handles timeouts" $ do
      (respondTo, deliverWithResponse) <- connect
      queueName <- randomQueueName

      respondTo queueName $ delayedResponder 20

      let response = deliverWithResponse R.newReq {
        R.queueName = queueName,
        R.body = requestBody,
        R.timeoutInMs = 10
      }

      response `shouldReturn` Left Freddy.TimeoutError

    it "returns a invalid request error when queue does not exist" $ do
      (_, deliverWithResponse) <- connect
      queueName <- randomQueueName

      let response = deliverWithResponse R.newReq {
        R.queueName = queueName,
        R.body = requestBody
      }

      response `shouldReturn` Left Freddy.InvalidRequest
