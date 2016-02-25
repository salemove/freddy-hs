{-# OPTIONS -XOverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import System.Random (randomIO)
import Data.UUID (UUID, toText)
import Data.Text (Text)
import Control.Concurrent (threadDelay)
import qualified Network.Freddy as Freddy

newUUID :: IO UUID
newUUID = randomIO

randomQueueName :: IO Text
randomQueueName = do
  uuid <- newUUID
  return $ toText uuid

echoResponder (Freddy.Request body replyWith failWith) = do
  replyWith body

delayedResponder (Freddy.Request body replyWith failWith) = do
  threadDelay $ 4 * 1000 * 1000 -- 4 seconds
  replyWith body

spec :: Spec
spec = do
  describe "Freddy" $ do
    it "can respond to messages" $ do
      (respondTo, deliverWithResponse) <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
      queueName <- randomQueueName

      respondTo queueName echoResponder

      let requestBody = "msg body"
      let response = deliverWithResponse queueName requestBody

      response `shouldReturn` Right requestBody

    it "handles timeouts" $ do
      (respondTo, deliverWithResponse) <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
      queueName <- randomQueueName

      respondTo queueName delayedResponder

      let requestBody = "msg body"
      let response = deliverWithResponse queueName requestBody

      response `shouldReturn` Left Freddy.TimeoutError
