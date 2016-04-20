{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

import qualified Network.Freddy as Freddy
import qualified Network.Freddy.Request as R
import GHC.Generics (Generic)
import Data.Aeson (ToJSON, encode)

data EchoRequest = EchoRequest {
  message :: String
} deriving (Generic, Show)

instance ToJSON EchoRequest

echo body = do
  let request = EchoRequest { message = body }
  connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"

  responseBody <- Freddy.deliverWithResponse connection R.newReq {
    R.queueName = "EchoServer",
    R.body = encode request
  }
  putStrLn $ "Got response: " ++ show responseBody

main = do
  putStrLn "Start echo_server.hs and execute:"
  putStrLn "  echo \"cookie monster\""
  putStrLn ""
