{-# OPTIONS -XOverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import System.Random (randomIO)
import Data.UUID (UUID, toText)
import Data.Text (Text)
import Control.Concurrent (threadDelay)
import qualified Network.Freddy as Freddy
import SpecHelper (
  newUUID,
  randomQueueName,
  echoResponder,
  delayedResponder,
  connect,
  requestBody
  )

spec :: Spec
spec = do
  describe "Freddy" $ do
    it "can respond to messages" $ do
      (respondTo, deliverWithResponse) <- connect
      queueName <- randomQueueName

      respondTo queueName echoResponder

      let response = deliverWithResponse queueName requestBody

      response `shouldReturn` Right requestBody

    it "handles timeouts" $ do
      (respondTo, deliverWithResponse) <- connect
      queueName <- randomQueueName

      respondTo queueName delayedResponder

      let response = deliverWithResponse queueName requestBody

      response `shouldReturn` Left Freddy.TimeoutError

    it "returns a invalid request error when queue does not exist" $ do
      (_, deliverWithResponse) <- connect
      queueName <- randomQueueName

      let response = deliverWithResponse queueName requestBody

      response `shouldReturn` Left Freddy.InvalidRequest
