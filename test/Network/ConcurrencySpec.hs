{-# LANGUAGE OverloadedStrings #-}
module Network.ConcurrencySpec where

import Test.Hspec
import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import Control.Concurrent.Async (forConcurrently)
import System.Timeout (timeout)
import Data.Maybe (isJust)
import SpecHelper (
  randomQueueName,
  requestBody,
  withConnection,
  delayedResponder
  )

spec :: Spec
spec = around withConnection $
  describe "Concurrency" $ do
    let buildRequest queueName = R.newReq {
      R.queueName = queueName,
      R.body = requestBody
    }

    it "runs responder in parallel" $ \connection -> do
      let deliveryCount = 4
      let responderDelayIsMs = 50
      let minSequentialRespondTimeInMs = deliveryCount * responderDelayIsMs
      let maxParallelRespondTimeInMs = minSequentialRespondTimeInMs - responderDelayIsMs

      queueName <- randomQueueName

      Freddy.respondTo connection queueName $ delayedResponder responderDelayIsMs

      result <- timeout (maxParallelRespondTimeInMs * 1000) $
        forConcurrently (replicate deliveryCount Nothing) $ \_ ->
          Freddy.deliverWithResponse connection $ buildRequest queueName

      let ranInParallel = return . isJust $ result

      ranInParallel `shouldReturn` True
