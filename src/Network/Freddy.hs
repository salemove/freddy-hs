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

import Control.Concurrent (forkIO)
import qualified Network.AMQP as AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Control.Concurrent.BroadcastChan as BC
import System.Timeout (timeout)
import Network.Freddy.ResultType (ResultType)
import qualified Network.Freddy.ResultType as ResultType
import qualified Network.Freddy.Request as Request
import Network.Freddy.CorrelationIdGenerator (CorrelationId, generateCorrelationId)

type Payload = ByteString
type QueueName = Text

type ReplyWith = Payload -> IO ()
type FailWith  = Payload -> IO ()

type ResponseChannelEmitter = BC.BroadcastChan BC.In (Maybe AMQP.PublishError, AMQP.Message)
type ResponseChannelListener = BC.BroadcastChan BC.Out (Maybe AMQP.PublishError, AMQP.Message)

data Error = InvalidRequest Payload | TimeoutError deriving (Show, Eq)
type Response = Either Error Payload

data Delivery = Delivery Payload ReplyWith FailWith
data Reply = Reply QueueName AMQP.Message

data Connection = Connection {
  amqpConnection :: AMQP.Connection,
  amqpProduceChannel :: AMQP.Channel,
  amqpResponseChannel :: AMQP.Channel,
  responseQueueName :: Text,
  eventChannel :: ResponseChannelEmitter
}

data Consumer = Consumer {
  consumerTag :: AMQP.ConsumerTag,
  consumerChannel :: AMQP.Channel
}

{-|
  Creates a connection with the message queue.

  __Example__:

  @
    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
  @
-}
connect :: String -- ^ server host
        -> Text   -- ^ virtual host
        -> Text   -- ^ user name
        -> Text   -- ^ password
        -> IO Connection
connect host vhost user pass = do
  connection <- AMQP.openConnection host vhost user pass
  produceChannel <- AMQP.openChannel connection
  responseChannel <- AMQP.openChannel connection

  AMQP.declareExchange produceChannel AMQP.newExchange {
    AMQP.exchangeName = topicExchange,
    AMQP.exchangeType = "topic",
    AMQP.exchangeDurable = False
  }

  eventChannel <- BC.newBroadcastChan

  (responseQueueName, _, _) <- declareQueue responseChannel ""
  AMQP.consumeMsgs responseChannel responseQueueName AMQP.NoAck $ responseCallback eventChannel

  AMQP.addReturnListener produceChannel (returnCallback eventChannel)

  return $ Connection {
    amqpConnection = connection,
    amqpResponseChannel = responseChannel,
    amqpProduceChannel = produceChannel,
    responseQueueName = responseQueueName,
    eventChannel = eventChannel
  }

{-|
  Closes the connection with the message queue.

  __Example__:

  @
    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
    Freddy.disconnect connection
  @
-}
disconnect :: Connection -> IO ()
disconnect = AMQP.closeConnection . amqpConnection

{-|
  Sends a message and waits for the response.

  __Example__:

  @
    import qualified Network.Freddy as Freddy
    import qualified Network.Freddy.Request as R

    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"

    response <- Freddy.deliverWithResponse connection R.newReq {
      R.queueName = "echo",
      R.body = "{\\"msg\\": \\"what did you say?\\"}"
    }

    case response of
      Right payload -> putStrLn "Received positive result"
      Left (Freddy.InvalidRequest payload) -> putStrLn "Received error"
      Left Freddy.TimeoutError -> putStrLn "Request timed out"
  @
-}
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

  responseChannelListener <- BC.newBChanListener $ eventChannel connection

  AMQP.publishMsg' (amqpProduceChannel connection) "" (Request.queueName request) True msg
  AMQP.publishMsg (amqpProduceChannel connection) topicExchange (Request.queueName request) msg

  responseBody <- timeout (Request.timeoutInMicroseconds request) $ do
    let messageMatcher = matchingCorrelationId correlationId
    waitForResponse responseChannelListener messageMatcher

  case responseBody of
    Just (Nothing, msg) -> return . createResponse $ msg
    Just (Just error, _) -> return . Left . InvalidRequest $ "Publish Error"
    Nothing -> return $ Left TimeoutError

createResponse :: AMQP.Message -> Either Error Payload
createResponse msg = do
  let msgBody = AMQP.msgBody msg

  case AMQP.msgType msg of
    Just msgType ->
      if (ResultType.fromText msgType) == ResultType.Success then
        Right msgBody
      else
        Left . InvalidRequest $ msgBody
    _ -> Left . InvalidRequest $ "No message type"

{-|
  Send and forget type of delivery. It sends a message to given destination
  without waiting for a response. This is useful when there are multiple
  consumers that are using 'tapInto' or you just do not care about the
  response.

  __Example__:

  @
    import qualified Network.Freddy as Freddy
    import qualified Network.Freddy.Request as R

    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
    Freddy.deliver connection R.newReq {
      R.queueName = "notifications.user_signed_in",
      R.body = "{\\"user_id\\": 1}"
    }
  @
-}
deliver :: Connection -> Request.Request -> IO ()
deliver connection request = do
  let msg = AMQP.newMsg {
    AMQP.msgBody         = Request.body request,
    AMQP.msgDeliveryMode = Just AMQP.NonPersistent,
    AMQP.msgExpiration   = Request.expirationInMs request
  }

  AMQP.publishMsg (amqpProduceChannel connection) "" (Request.queueName request) msg
  AMQP.publishMsg (amqpProduceChannel connection) topicExchange (Request.queueName request) msg

{-|
  Responds to messages on a given destination. It is useful for messages that
  have to be processed once and then a result must be sent.

  __Example__:

  @
    processMessage (Freddy.Delivery body replyWith failWith) = replyWith body

    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
    Freddy.respondTo connection "echo" processMessage
  @
-}
respondTo :: Connection -> QueueName -> (Delivery -> IO ()) -> IO Consumer
respondTo connection queueName callback = do
  let produceChannel = amqpProduceChannel connection
  consumeChannel <- AMQP.openChannel . amqpConnection $ connection
  declareQueue consumeChannel queueName
  tag <- AMQP.consumeMsgs consumeChannel queueName AMQP.NoAck $
    replyCallback callback produceChannel
  return Consumer { consumerChannel = consumeChannel, consumerTag = tag }

{-|
  Listens for messages on a given destination or destinations without
  consuming them.

  __Example__:

  @
    processMessage body = putStrLn body

    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
    Freddy.tapInto connection "notifications.*" processMessage
  @
-}
tapInto :: Connection -> QueueName -> (Payload -> IO ()) -> IO Consumer
tapInto connection queueName callback = do
  consumeChannel <- AMQP.openChannel . amqpConnection $ connection

  declareExlusiveQueue consumeChannel queueName
  AMQP.bindQueue consumeChannel "" topicExchange queueName

  let consumer = callback . AMQP.msgBody .fst
  tag <- AMQP.consumeMsgs consumeChannel queueName AMQP.NoAck consumer

  return Consumer { consumerChannel = consumeChannel, consumerTag = tag }

{-|
  Stops the consumer from listening new messages.

  __Example__:

  @
    connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
    consumer <- Freddy.tapInto connection "notifications.*" processMessage
    threadDelay tenMinutes $ Freddy.cancelConsumer consumer
  @
-}
cancelConsumer :: Consumer -> IO ()
cancelConsumer consumer = do
  AMQP.cancelConsumer (consumerChannel consumer) $ consumerTag consumer
  AMQP.closeChannel (consumerChannel consumer)

returnCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.PublishError) -> IO ()
returnCallback eventChannel (msg, error) =
  BC.writeBChan eventChannel (Just error, msg)

responseCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.Envelope) -> IO ()
responseCallback eventChannel (msg, _) =
  BC.writeBChan eventChannel (Nothing, msg)

replyCallback :: (Delivery -> IO ()) -> AMQP.Channel -> (AMQP.Message, AMQP.Envelope) -> IO ()
replyCallback userCallback channel (msg, env) = do
  let requestBody = AMQP.msgBody msg
  let replyWith = sendReply msg channel ResultType.Success
  let failWith = sendReply msg channel ResultType.Error
  let delivery = Delivery requestBody replyWith failWith
  forkIO . userCallback $ delivery
  return ()

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
    AMQP.msgType          = Just . ResultType.serializeResultType $ resType
  }

  Just $ Reply queueName msg

matchingCorrelationId :: CorrelationId -> AMQP.Message -> Bool
matchingCorrelationId correlationId msg =
  case AMQP.msgCorrelationID msg of
    Just msgCorrelationId -> msgCorrelationId == correlationId
    Nothing -> False

topicExchange :: Text
topicExchange = "freddy-topic"

waitForResponse :: ResponseChannelListener -> (AMQP.Message -> Bool) -> IO (Maybe AMQP.PublishError, AMQP.Message)
waitForResponse eventChannelListener predicate = do
  (error, msg) <- BC.readBChan eventChannelListener

  if predicate msg then
    return (error, msg)
  else
    waitForResponse eventChannelListener predicate

declareQueue :: AMQP.Channel -> QueueName -> IO (Text, Int, Int)
declareQueue channel queueName =
  AMQP.declareQueue channel AMQP.newQueue {AMQP.queueName = queueName}

declareExlusiveQueue :: AMQP.Channel -> QueueName -> IO (Text, Int, Int)
declareExlusiveQueue channel queueName =
  AMQP.declareQueue channel AMQP.newQueue {
    AMQP.queueName = queueName,
    AMQP.queueExclusive = True
  }
