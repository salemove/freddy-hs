{-# OPTIONS -XOverloadedStrings #-}
module Network.Freddy (connect, respondTo, Request (..)) where

import Network.AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import Network.Freddy.ResultType (ResultType (..), serializeResultType)

type RequestBody = ByteString
type ReplyBody   = ByteString
type ReplyWith   = ByteString -> IO ()
type FailWith    = ByteString -> IO ()
data Request     = Request RequestBody ReplyWith FailWith

connect :: String -> Text -> Text -> Text -> IO Connection
connect = openConnection

respondTo :: Connection -> String -> (Request -> IO ()) -> IO ()
respondTo conn queueName callback = do
  chan <- openChannel conn
  declareQueue chan newQueue {queueName = pack queueName}
  consumeMsgs chan (pack queueName) NoAck (replyCallback callback chan)
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
    Just (queueName, reply) -> (publishMsg channel "" queueName reply)
    Nothing -> putStrLn $ "Could not reply"

buildReply :: Message -> ResultType -> ByteString -> Maybe (Text, Message)
buildReply originalMsg resType body = do
  queueName <- msgReplyTo originalMsg

  let reply = newMsg {
    msgBody          = body,
    msgCorrelationID = msgCorrelationID originalMsg,
    msgDeliveryMode  = Just NonPersistent,
    msgType          = Just $ pack $ serializeResultType resType
  }

  Just $ (queueName, reply)
