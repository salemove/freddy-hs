{-# OPTIONS -XOverloadedStrings #-}
module SpecHelper where
  import System.Random (randomIO)
  import Data.UUID (UUID, toText)
  import Data.Text (Text)
  import Control.Concurrent (threadDelay)
  import qualified Network.Freddy as Freddy
  import Data.ByteString.Lazy.Char8 (ByteString)

  newUUID :: IO UUID
  newUUID = randomIO

  randomQueueName :: IO Text
  randomQueueName = do
    uuid <- newUUID
    return $ toText uuid

  echoResponder (Freddy.Request body replyWith failWith) = do
    replyWith body

  delayedResponder (Freddy.Request body replyWith failWith) = do
    threadDelay $ 4 * 1000 * 1000 -- 4 seconds
    replyWith body

  connect = Freddy.connect "127.0.0.1" "/" "guest" "guest"

  requestBody :: ByteString
  requestBody = "request body"
