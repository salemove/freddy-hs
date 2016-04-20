{-# LANGUAGE OverloadedStrings #-}
module SpecHelper where
  import System.Random (randomIO)
  import Data.UUID (UUID, toText)
  import Data.Text (Text)
  import Control.Concurrent (threadDelay, putMVar, newEmptyMVar, takeMVar)
  import qualified Network.Freddy as Freddy
  import Data.ByteString.Lazy.Char8 (ByteString)
  import System.Timeout (timeout)

  newUUID :: IO UUID
  newUUID = randomIO

  randomQueueName :: IO Text
  randomQueueName = do
    uuid <- newUUID
    return $ toText uuid

  echoResponder (Freddy.Request body replyWith _) =
    replyWith body

  delayedResponder delayInMs (Freddy.Request body replyWith _) = do
    threadDelay $ delayInMs * 1000
    replyWith body

  storeResponder gotResult (Freddy.Request body replyWith _) = do
    putMVar gotResult True
    replyWith body

  createQueue connection queueName = do
    consumer <- Freddy.respondTo connection queueName echoResponder
    Freddy.cancelConsumer connection consumer

  processRequest connection queueName = do
    gotRequestStore <- newEmptyMVar
    Freddy.respondTo connection queueName $ storeResponder gotRequestStore
    result <- timeout (20 * 1000) (takeMVar gotRequestStore)
    case result of
      Just True -> return True
      Nothing -> return False

  connect = Freddy.connect "127.0.0.1" "/" "guest" "guest"

  requestBody :: ByteString
  requestBody = "request body"
