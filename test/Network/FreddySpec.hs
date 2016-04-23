{-# LANGUAGE OverloadedStrings #-}
module Network.FreddySpec where

import Test.Hspec
import qualified Data.ByteString.Lazy.Char8 as BS
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import qualified Data.Text as Text
import SpecHelper (
  randomQueueName,
  echoResponder,
  errorResponder,
  requestBody,
  withConnection,
  createQueue,
  processRequest,
  waitFromStore,
  tapIntoOnce
  )

spec :: Spec
spec = around withConnection $
  describe "Freddy" $ do
    let buildRequest queueName = R.newReq {
      R.queueName = queueName,
      R.body = requestBody
    }

    it "responds to a message with success" $ \connection -> do
      queueName <- randomQueueName

      Freddy.respondTo connection queueName echoResponder

      let response = Freddy.deliverWithResponse connection (buildRequest queueName)

      response `shouldReturn` Right requestBody

    it "responds to a message with error" $ \connection -> do
      queueName <- randomQueueName

      Freddy.respondTo connection queueName errorResponder

      let response = Freddy.deliverWithResponse connection (buildRequest queueName)

      response `shouldReturn` (Left . Freddy.InvalidRequest $ requestBody)

    it "returns invalid request error when queue does not exist" $ \connection -> do
      queueName <- randomQueueName

      let response = Freddy.deliverWithResponse connection (buildRequest queueName)

      response `shouldReturn` (Left . Freddy.InvalidRequest $ "Publish Error")

    it "sends and forgets a message" $ \connection -> do
      queueName <- randomQueueName
      createQueue connection queueName

      Freddy.deliver connection (buildRequest queueName)

      let gotRequest = processRequest connection queueName
      gotRequest `shouldReturn` True

    it "taps into a queue" $ \connection -> do
      queueName <- randomQueueName

      receivedMsgStore <- tapIntoOnce connection queueName
      Freddy.deliver connection $ buildRequest queueName

      let receivedMsg = waitFromStore receivedMsgStore
      receivedMsg `shouldReturn` Just requestBody

    it "taps into a wildcard queue" $ \connection -> do
      baseQueueName <- randomQueueName
      let wildQueueName = Text.append baseQueueName ".*"
      let specificQueueName = Text.append baseQueueName ".sub"

      receivedMsgStore <- tapIntoOnce connection wildQueueName
      Freddy.deliver connection $ buildRequest specificQueueName

      let receivedMsg = waitFromStore receivedMsgStore
      receivedMsg `shouldReturn` Just requestBody
