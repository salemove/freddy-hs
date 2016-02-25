{-# OPTIONS -XOverloadedStrings #-}
module Network.Freddy (connect, Request (..), Error (..)) where

import qualified Network.AMQP as AMQP
import Data.Text (Text)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Control.Concurrent.BroadcastChan as BC
import Control.Concurrent (forkIO)
import qualified Data.UUID as UUID
import Data.UUID (UUID)
import System.Random (randomIO)
import System.Timeout (timeout)

import Network.Freddy.ResultType (ResultType (..), serializeResultType)

type RequestBody = ByteString
type ResponseBody = ByteString
type ReplyBody = ByteString
type QueueName = Text
type CorrelationId = Text

type ReplyWith = ByteString -> IO ()
type FailWith  = ByteString -> IO ()

type RespondTo = QueueName -> (Request -> IO ()) -> IO ()
type DeliverWithResponse = QueueName -> RequestBody -> IO Response
type Handlers = IO (RespondTo, DeliverWithResponse)

type ResponseChannelEmitter = BC.BroadcastChan BC.In AMQP.Message
type ResponseChannelListener = BC.BroadcastChan BC.Out AMQP.Message

data Error = InvalidRequest | TimeoutError deriving (Show, Eq)
type Response = Either Error ResponseBody

data Request = Request RequestBody ReplyWith FailWith
data Reply = Reply QueueName AMQP.Message

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

  let publicRespondTo = respondTo channel
  let publicDeliverWithResponse = deliverWithResponse channel responseQueueName responseChannelListener

  return (publicRespondTo, publicDeliverWithResponse)

responseCallback :: ResponseChannelEmitter -> (AMQP.Message, AMQP.Envelope) -> IO ()
responseCallback eventChannel (msg, env) =
  BC.writeBChan eventChannel msg

respondTo :: AMQP.Channel -> QueueName -> (Request -> IO ()) -> IO ()
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
    Nothing -> putStrLn $ "Could not reply"

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

deliverWithResponse :: AMQP.Channel -> QueueName -> ResponseChannelListener -> QueueName -> RequestBody -> IO Response
deliverWithResponse channel responseQueueName responseChannelListener queueName body = do
  correlationId <- generateCorrelationId

  let msg = AMQP.newMsg {
    AMQP.msgBody          = body,
    AMQP.msgCorrelationID = Just $ correlationId,
    AMQP.msgDeliveryMode  = Just AMQP.NonPersistent,
    AMQP.msgType          = Just $ "request",
    AMQP.msgReplyTo       = Just $ responseQueueName
  }

  AMQP.publishMsg channel "" queueName msg

  responseBody <- timeout (3 * 1000 * 1000) (waitForResponse responseChannelListener correlationId $ matchingCorrelationId correlationId)

  case responseBody of
    Just body -> return $ Right body
    Nothing -> return $ Left $ TimeoutError

matchingCorrelationId :: CorrelationId -> AMQP.Message -> Bool
matchingCorrelationId correlationId msg =
  case AMQP.msgCorrelationID msg of
    Just msgCorrelationId -> msgCorrelationId == correlationId
    Nothing -> False

waitForResponse :: ResponseChannelListener -> CorrelationId -> (AMQP.Message -> Bool) -> IO ResponseBody
waitForResponse eventChannelListener correlationId predicate = do
  msg <- BC.readBChan eventChannelListener

  if predicate msg then
    return $ AMQP.msgBody msg
  else
    waitForResponse eventChannelListener correlationId predicate

generateCorrelationId :: IO CorrelationId
generateCorrelationId = do
  uuid <- newUUID
  return $ UUID.toText uuid

newUUID :: IO UUID
newUUID = randomIO
