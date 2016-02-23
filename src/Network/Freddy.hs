{-# OPTIONS -XOverloadedStrings #-}
module Network.Freddy (connect, respondTo, Request (..), deliverWithResponse) where

import Network.AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import Network.Freddy.ResultType (ResultType (..), serializeResultType)
--import Control.Concurrent
--import Control.Concurrent.STM
import qualified Control.Concurrent.CML as CML
import Control.Monad.IO.Class

type RequestBody = ByteString
type ReplyWith   = ByteString -> IO ()
type FailWith    = ByteString -> IO ()
data Request     = Request RequestBody ReplyWith FailWith

type ReplyBody   = ByteString
type Queue       = Text
data Reply       = Reply Queue Message

type QueueName = String
type Responder = QueueName -> (Request -> IO ())

--connect :: String -> Text -> Text -> Text -> IO (QueueName -> (Request -> IO ()) -> IO ())
connect host vhost user pass = do
  connection <- openConnection host vhost user pass
  channel <- openChannel connection

  eventChannel <- CML.channel

  (responseQueueName, _, _) <- declareQueue channel newQueue {queueName = ""}
  consumeMsgs channel responseQueueName NoAck (responseCallback eventChannel)

  let publicRespondTo = respondTo channel
  let publicDeliverWithResponse = deliverWithResponse channel responseQueueName eventChannel

  return (publicRespondTo, publicDeliverWithResponse)

--responseCallback :: CML.Channel Message -> (Message, Envelope) -> IO ()
responseCallback :: CML.Channel Message -> (Message, Envelope) -> IO ()
responseCallback eventChannel (msg, env) =
  liftIO (CML.spawn $ CML.sync $ (CML.transmit eventChannel msg)) >> return ()

respondTo :: Channel -> QueueName -> (Request -> IO ()) -> IO ()
respondTo channel queueName callback = do
  declareQueue channel newQueue {queueName = pack queueName}
  consumeMsgs channel (pack queueName) NoAck (replyCallback callback channel)
  return ()

replyCallback :: (Request -> t) -> Channel -> (Message, t1) -> t
replyCallback userCallback channel (msg, env) = do
  let requestBody = msgBody msg
  let replyWith = sendReply msg channel Success
  let failWith = sendReply msg channel Error
  userCallback $ Request requestBody replyWith failWith

sendReply :: Message -> Channel -> ResultType -> ReplyBody -> IO ()
sendReply originalMsg channel resType body =
  case buildReply originalMsg resType body of
    Just (Reply queueName message) -> (publishMsg channel "" queueName message)
    Nothing -> putStrLn $ "Could not reply"

buildReply :: Message -> ResultType -> ReplyBody -> Maybe Reply
buildReply originalMsg resType body = do
  queueName <- msgReplyTo originalMsg

  let msg = newMsg {
    msgBody          = body,
    msgCorrelationID = msgCorrelationID originalMsg,
    msgDeliveryMode  = Just NonPersistent,
    msgType          = Just $ pack $ serializeResultType resType
  }

  Just $ Reply queueName msg

--deliverWithResponse :: Channel -> Text -> String -> ByteString -> (ByteString -> t1) -> t2
deliverWithResponse channel responseQueueName eventChannel queueName body callback = do
  let msg = newMsg {
    msgBody          = body,
    msgCorrelationID = Just "correlation-id",
    msgDeliveryMode  = Just NonPersistent,
    msgType          = Just $ "request",
    msgReplyTo       = Just $ responseQueueName
  }

  publishMsg channel "" queueName msg

  blabla eventChannel callback

  return ()

blabla :: CML.Channel Message -> (ByteString -> IO ()) -> IO ()
blabla eventChannel callback = do
  msg <- CML.sync $ CML.receive eventChannel (const True)
  callback $ msgBody msg
  return ()
