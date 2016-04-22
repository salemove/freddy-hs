{-# LANGUAGE OverloadedStrings #-}
module SpecHelper where
  import System.Random (randomIO)
  import Data.UUID (UUID, toText)
  import Data.Text (Text)
  import Control.Concurrent (threadDelay, putMVar, newEmptyMVar, takeMVar)
  import qualified Network.Freddy as Freddy
  import Data.ByteString.Lazy.Char8 (ByteString)
  import System.Timeout (timeout)

  withConnection example = do
    connection <- connect
    example connection
    Freddy.disconnect connection

  randomQueueName :: IO Text
  randomQueueName = do
    uuid <- (randomIO :: IO UUID)
    return $ toText uuid

  echoResponder (Freddy.Delivery body replyWith _) =
    replyWith body

  errorResponder (Freddy.Delivery body _ failWith) =
    failWith body

  delayedResponder delayInMs (Freddy.Delivery body replyWith _) = do
    threadDelay $ delayInMs * 1000
    replyWith body

  storeResponder gotResult (Freddy.Delivery body replyWith _) = do
    putMVar gotResult True
    replyWith body

  createQueue connection queueName = do
    consumer <- Freddy.respondTo connection queueName echoResponder
    Freddy.cancelConsumer consumer

  processRequest connection queueName = do
    gotRequestStore <- newEmptyMVar
    Freddy.respondTo connection queueName $ storeResponder gotRequestStore
    result <- waitFromStore gotRequestStore
    case result of
      Just True -> return True
      Nothing -> return False

  tapIntoOnce connection queueName = do
    receivedMsgStore <- newEmptyMVar
    Freddy.tapInto connection queueName $ \body ->
      putMVar receivedMsgStore body
    return receivedMsgStore

  waitFromStore store =
    timeout (100 * 1000) $ takeMVar store

  connect = Freddy.connect "127.0.0.1" "/" "guest" "guest"

  requestBody :: ByteString
  requestBody = "request body"
