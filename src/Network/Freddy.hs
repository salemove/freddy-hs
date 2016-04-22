{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy (
  connect,
  disconnect,
  Connection,
  respondTo,
  tapInto,
  deliverWithResponse,
  deliver,
  cancelConsumer,
  Consumer,
  Delivery (..),
  Error (..)
) where

import qualified Network.AMQP as AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Control.Concurrent.BroadcastChan as BC
import System.Timeout (timeout)

import Network.Freddy.ResultType (ResultType (..), serializeResultType)
import qualified Network.Freddy.Request as Request
import Network.Freddy.CorrelationIdGenerator (CorrelationId, generateCorrelationId)

type Payload = ByteString
type QueueName = Text

type ReplyWith = Payload -> IO ()
type FailWith  = Payload -> IO ()

type ResponseChannelEmitter = BC.BroadcastChan BC.In AMQPResponse
type ResponseChannelListener = BC.BroadcastChan BC.Out AMQPResponse

data Error = InvalidRequest | TimeoutError deriving (Show, Eq)
type Response = Either Error Payload

data Delivery = Delivery Payload ReplyWith FailWith
data Reply = Reply QueueName AMQP.Message

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

disconnect :: Connection -> IO ()
disconnect = AMQP.closeConnection . amqpConnection

deliverWithResponse :: Connection -> Request.Request -> IO Response
deliverWithResponse connection request = do
  correlationId <- generateCorrelationId

  let msg = AMQP.newMsg {
    AMQP.msgBody          = Request.body request,
    AMQP.msgCorrelationID = Just correlationId,
    AMQP.msgDeliveryMode  = Just AMQP.NonPersistent,
    AMQP.msgType          = Just "request",
    AMQP.msgReplyTo       = Just $ responseQueueName connection,
    AMQP.msgExpiration    = Request.expirationInMs request
  }

  AMQP.publishMsg' (amqpChannel connection) "" (Request.queueName request) True msg
  AMQP.publishMsg (amqpChannel connection) topicExchange (Request.queueName request) msg

  responseBody <- timeout (Request.timeoutInMicroseconds request) $
    waitForResponse (responseChannelListener connection) correlationId $ matchingCorrelationId correlationId

  case responseBody of
    Just (Right body) -> return . Right . AMQP.msgBody $ body
    Just (Left error) -> return . Left $ InvalidRequest
    Nothing -> return $ Left TimeoutError

deliver :: Connection -> Request.Request -> IO ()
deliver connection request = do
  let msg = AMQP.newMsg {
    AMQP.msgBody         = Request.body request,
    AMQP.msgDeliveryMode = Just AMQP.NonPersistent,
    AMQP.msgExpiration   = Request.expirationInMs request
  }

  AMQP.publishMsg (amqpChannel connection) "" (Request.queueName request) msg
  AMQP.publishMsg (amqpChannel connection) topicExchange (Request.queueName request) msg

respondTo :: Connection -> QueueName -> (Delivery -> IO ()) -> IO Consumer
respondTo connection queueName callback = do
  let channel = amqpChannel connection
  AMQP.declareQueue channel AMQP.newQueue {AMQP.queueName = queueName}
  tag <- AMQP.consumeMsgs channel queueName AMQP.NoAck (replyCallback callback channel)
  return Consumer { consumerChannel = channel, consumerTag = tag }

tapInto :: Connection -> QueueName -> (Payload -> IO ()) -> IO Consumer
tapInto connection queueName callback = do
  let channel = amqpChannel connection

  AMQP.declareQueue channel AMQP.newQueue {
    AMQP.queueName = queueName,
    AMQP.queueExclusive = True
  }
  AMQP.declareExchange channel AMQP.newExchange {
    AMQP.exchangeName = topicExchange,
    AMQP.exchangeType = "topic",
    AMQP.exchangeDurable = False
  }
  AMQP.bindQueue channel "" topicExchange queueName

  let consumer = callback . AMQP.msgBody .fst
  tag <- AMQP.consumeMsgs channel queueName AMQP.NoAck consumer

  return Consumer { consumerChannel = channel, consumerTag = tag }

cancelConsumer :: Consumer -> IO ()
cancelConsumer consumer =
  AMQP.cancelConsumer (consumerChannel consumer) $ consumerTag consumer

returnCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.PublishError) -> IO ()
returnCallback eventChannel (msg, error) =
  BC.writeBChan eventChannel (Left error)

responseCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.Envelope) -> IO ()
responseCallback eventChannel (msg, env) =
  BC.writeBChan eventChannel (Right msg)

replyCallback :: (Delivery -> t) -> AMQP.Channel -> (AMQP.Message, AMQP.Envelope) -> t
replyCallback userCallback channel (msg, env) = do
  let requestBody = AMQP.msgBody msg
  let replyWith = sendReply msg channel Success
  let failWith = sendReply msg channel Error
  userCallback $ Delivery requestBody replyWith failWith

sendReply :: AMQP.Message -> AMQP.Channel -> ResultType -> Payload -> IO ()
sendReply originalMsg channel resType body =
  case buildReply originalMsg resType body of
    Just (Reply queueName message) -> AMQP.publishMsg channel "" queueName message
    Nothing -> putStrLn "Could not reply"

buildReply :: AMQP.Message -> ResultType -> Payload -> Maybe Reply
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

topicExchange :: Text
topicExchange = "freddy-topic"

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
