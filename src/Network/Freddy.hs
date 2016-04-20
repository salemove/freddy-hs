{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy (connect, Request (..), Error (..)) where

import qualified Network.AMQP as AMQP
import Data.Text (Text)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Control.Concurrent.BroadcastChan as BC
import qualified Data.UUID as UUID
import Data.UUID (UUID)
import System.Random (randomIO)
import System.Timeout (timeout)

import Network.Freddy.ResultType (ResultType (..), serializeResultType)
import qualified Network.Freddy.Request as DWP

type RequestBody = ByteString
type ResponseBody = ByteString
type ReplyBody = ByteString
type ResponderQueueName = Text
type ResponseQueueName = Text
type CorrelationId = Text

type ReplyWith = ByteString -> IO ()
type FailWith  = ByteString -> IO ()

type RespondTo = ResponderQueueName -> (Request -> IO ()) -> IO ()
type DeliverWithResponse = DWP.Request -> IO Response
type Handlers = IO (RespondTo, DeliverWithResponse)

type ResponseChannelEmitter = BC.BroadcastChan BC.In AMQPResponse
type ResponseChannelListener = BC.BroadcastChan BC.Out AMQPResponse

data Error = InvalidRequest | TimeoutError deriving (Show, Eq)
type Response = Either Error ResponseBody

data Request = Request RequestBody ReplyWith FailWith
data Reply = Reply ResponseQueueName AMQP.Message

type AMQPResponse = Either AMQP.PublishError AMQP.Message

connect :: String -> Text -> Text -> Text -> Handlers
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

  let publicRespondTo = respondTo channel
  let publicDeliverWithResponse = deliverWithResponse channel responseQueueName responseChannelListener

  return (publicRespondTo, publicDeliverWithResponse)

returnCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.PublishError) -> IO ()
returnCallback eventChannel (msg, error) =
  BC.writeBChan eventChannel (Left error)

responseCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.Envelope) -> IO ()
responseCallback eventChannel (msg, env) =
  BC.writeBChan eventChannel (Right msg)

respondTo :: AMQP.Channel -> ResponderQueueName -> (Request -> IO ()) -> IO ()
respondTo channel queueName callback = do
  AMQP.declareQueue channel AMQP.newQueue {AMQP.queueName = queueName}
  AMQP.consumeMsgs channel queueName AMQP.NoAck (replyCallback callback channel)
  return ()

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
    AMQP.msgType          = Just $ serializeResultType resType
  }

  Just $ Reply queueName msg

deliverWithResponse :: AMQP.Channel -> ResponseQueueName -> ResponseChannelListener -> DWP.Request -> IO Response
deliverWithResponse channel responseQueueName responseChannelListener request = do
  correlationId <- generateCorrelationId

  let msg = AMQP.newMsg {
    AMQP.msgBody          = DWP.body request,
    AMQP.msgCorrelationID = Just correlationId,
    AMQP.msgDeliveryMode  = Just AMQP.NonPersistent,
    AMQP.msgType          = Just "request",
    AMQP.msgReplyTo       = Just responseQueueName
  }

  AMQP.publishMsg' channel "" (DWP.queueName request) True msg
  let timeoutInMicroseconds = (DWP.timeoutInMs request) * 1000

  responseBody <- timeout timeoutInMicroseconds $
    waitForResponse responseChannelListener correlationId $ matchingCorrelationId correlationId

  case responseBody of
    Just (Right body) -> return $ Right $ AMQP.msgBody body
    Just (Left error) -> return $ Left InvalidRequest
    Nothing -> return $ Left TimeoutError

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

generateCorrelationId :: IO CorrelationId
generateCorrelationId = do
  uuid <- newUUID
  return $ UUID.toText uuid

newUUID :: IO UUID
newUUID = randomIO
