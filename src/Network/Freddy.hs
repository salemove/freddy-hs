{-# OPTIONS -XOverloadedStrings #-}
module Network.Freddy (connect, respondTo) where

import Network.AMQP
import Data.Text (Text, pack)
import Data.ByteString.Lazy.Char8 (ByteString)
import Network.Freddy.Result

connect :: String -> Text -> Text -> Text -> IO Connection
connect host vhost user password =
  openConnection host vhost user password

respondTo :: Connection -> String -> (ByteString -> Either ByteString ByteString) -> IO ConsumerTag
respondTo conn queueName callback = do
  chan <- openChannel conn

  declareQueue chan newQueue {queueName = pack queueName}

  consumeMsgs chan (pack queueName) NoAck (replyCallback callback chan)

replyCallback :: (ByteString -> Either ByteString ByteString) -> Channel -> (Message, Envelope) -> IO ()
replyCallback userCallback channel (msg, env) = do
  let (resType, body) = processRequest userCallback msg

  case buildReply msg resType body of
    Just (queueName, reply) -> (publishMsg channel "" queueName reply)
    Nothing -> putStrLn $ "Could not reply"

buildReply :: Message -> Result -> ByteString -> Maybe (Text, Message)
buildReply originalMsg resType body = do
  queueName <- msgReplyTo originalMsg

  let reply = newMsg {
    msgBody          = body,
    msgCorrelationID = msgCorrelationID originalMsg,
    msgDeliveryMode  = Just NonPersistent,
    msgType          = Just $ pack $ show resType
  }

  Just $ (queueName, reply)

processRequest :: (ByteString -> Either ByteString ByteString) -> Message -> (Result, ByteString)
processRequest userCallback msg = do
  let requestBody = msgBody msg

  case userCallback requestBody of
    Right r -> (Success, r)
    Left r -> (Error, r)
