{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy (
  connect,
  Connection,
  Consumer,
  Request (..),
  Error (..),
  respondTo,
  deliverWithResponse,
  cancelConsumer
) where

import qualified Network.AMQP as AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Control.Concurrent.BroadcastChan as BC
import System.Timeout (timeout)

import Network.Freddy.ResultType (ResultType (..), serializeResultType)
import qualified Network.Freddy.Request as DWP
import Network.Freddy.CorrelationIdGenerator (CorrelationId, generateCorrelationId)

type RequestBody = ByteString
type ResponseBody = ByteString
type ReplyBody = ByteString
type ResponderQueueName = Text
type ResponseQueueName = Text

type ReplyWith = ByteString -> IO ()
type FailWith  = ByteString -> IO ()

type RespondTo = ResponderQueueName -> (Request -> IO ()) -> IO AMQP.ConsumerTag
type DeliverWithResponse = DWP.Request -> IO Response
type CancelConsumer = AMQP.ConsumerTag -> IO ()
type Handlers = IO (RespondTo, DeliverWithResponse, CancelConsumer)

type ResponseChannelEmitter = BC.BroadcastChan BC.In AMQPResponse
type ResponseChannelListener = BC.BroadcastChan BC.Out AMQPResponse

data Error = InvalidRequest | TimeoutError deriving (Show, Eq)
type Response = Either Error ResponseBody

data Request = Request RequestBody ReplyWith FailWith
data Reply = Reply ResponseQueueName AMQP.Message

type AMQPResponse = Either AMQP.PublishError AMQP.Message

data Connection = Connection {
  amqpConnection :: AMQP.Connection,
  amqpChannel :: AMQP.Channel,
  responseQueueName :: Text,
  responseChannelListener :: ResponseChannelListener
}

data Consumer = Consumer {
  consumerTag :: AMQP.ConsumerTag,
  consumerChannel :: AMQP.Channel
}

connect :: String -> Text -> Text -> Text -> IO Connection
connect host vhost user pass = do
  connection <- AMQP.openConnection host vhost user pass
  channel <- AMQP.openChannel connection

  eventChannel <- BC.newBroadcastChan
  responseChannelListener <- BC.newBChanListener eventChannel

  (responseQueueName, _, _) <- AMQP.declareQueue channel AMQP.newQueue {
    AMQP.queueName = ""
  }
  AMQP.consumeMsgs channel responseQueueName AMQP.NoAck $ responseCallback eventChannel

  AMQP.addReturnListener channel (returnCallback eventChannel)

  return $ Connection {
    amqpConnection = connection,
    amqpChannel = channel,
    responseQueueName = responseQueueName,
    responseChannelListener = responseChannelListener
  }

deliverWithResponse :: Connection -> DWP.Request -> IO Response
deliverWithResponse connection request = do
  let timeoutInMs = DWP.timeoutInMs request
  let expiration = if DWP.deleteOnTimeout request
                     then Just . pack . show $ timeoutInMs
                     else Nothing

  correlationId <- generateCorrelationId

  let msg = AMQP.newMsg {
    AMQP.msgBody          = DWP.body request,
    AMQP.msgCorrelationID = Just correlationId,
    AMQP.msgDeliveryMode  = Just AMQP.NonPersistent,
    AMQP.msgType          = Just "request",
    AMQP.msgReplyTo       = Just $ responseQueueName connection,
    AMQP.msgExpiration    = expiration
  }

  AMQP.publishMsg' (amqpChannel connection) "" (DWP.queueName request) True msg

  responseBody <- timeout (timeoutInMs * 1000) $
    waitForResponse (responseChannelListener connection) correlationId $ matchingCorrelationId correlationId

  case responseBody of
    Just (Right body) -> return . Right . AMQP.msgBody $ body
    Just (Left error) -> return . Left $ InvalidRequest
    Nothing -> return $ Left TimeoutError

respondTo :: Connection -> ResponderQueueName -> (Request -> IO ()) -> IO Consumer
respondTo connection queueName callback = do
  let channel = amqpChannel connection
  AMQP.declareQueue channel AMQP.newQueue {AMQP.queueName = queueName}
  tag <- AMQP.consumeMsgs channel queueName AMQP.NoAck (replyCallback callback channel)
  return Consumer { consumerChannel = channel, consumerTag = tag }

cancelConsumer :: Consumer -> IO ()
cancelConsumer consumer =
  AMQP.cancelConsumer (consumerChannel consumer) (consumerTag consumer)

returnCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.PublishError) -> IO ()
returnCallback eventChannel (msg, error) =
  BC.writeBChan eventChannel (Left error)

responseCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.Envelope) -> IO ()
responseCallback eventChannel (msg, env) =
  BC.writeBChan eventChannel (Right msg)

replyCallback :: (Request -> t) -> AMQP.Channel -> (AMQP.Message, AMQP.Envelope) -> t
replyCallback userCallback channel (msg, env) = do
  let requestBody = AMQP.msgBody msg
  let replyWith = sendReply msg channel Success
  let failWith = sendReply msg channel Error
  userCallback $ Request requestBody replyWith failWith

sendReply :: AMQP.Message -> AMQP.Channel -> ResultType -> ReplyBody -> IO ()
sendReply originalMsg channel resType body =
  case buildReply originalMsg resType body of
    Just (Reply queueName message) -> AMQP.publishMsg channel "" queueName message
    Nothing -> putStrLn "Could not reply"

buildReply :: AMQP.Message -> ResultType -> ReplyBody -> Maybe Reply
buildReply originalMsg resType body = do
  queueName <- AMQP.msgReplyTo originalMsg

  let msg = AMQP.newMsg {
    AMQP.msgBody          = body,
    AMQP.msgCorrelationID = AMQP.msgCorrelationID originalMsg,
    AMQP.msgDeliveryMode  = Just AMQP.NonPersistent,
    AMQP.msgType          = Just . serializeResultType $ resType
  }

  Just $ Reply queueName msg

matchingCorrelationId :: CorrelationId -> AMQP.Message -> Bool
matchingCorrelationId correlationId msg =
  case AMQP.msgCorrelationID msg of
    Just msgCorrelationId -> msgCorrelationId == correlationId
    Nothing -> False

waitForResponse :: ResponseChannelListener -> CorrelationId -> (AMQP.Message -> Bool) -> IO AMQPResponse
waitForResponse eventChannelListener correlationId predicate = do
  amqpResponse <- BC.readBChan eventChannelListener

  case amqpResponse of
    Right msg ->
      if predicate msg then
        return amqpResponse
      else
        waitForResponse eventChannelListener correlationId predicate
    Left error ->
      -- TODO: Check routing key. This is needed when having multiple threads.
      return amqpResponse
