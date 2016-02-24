{-# OPTIONS -XOverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

import qualified Network.Freddy as Freddy
import GHC.Generics (Generic)
import Data.Aeson (ToJSON, encode)

data EchoRequest = EchoRequest {
  message :: String
} deriving (Generic, Show)

instance ToJSON EchoRequest

echo body = do
  let request = EchoRequest { message = body }
  (_, deliverWithResponse) <- Freddy.connect "127.0.0.1" "/" "guest" "guest"

  responseBody <- deliverWithResponse "EchoServer" (encode request)
  putStrLn $ "Got response: " ++ show responseBody

main = do
  putStrLn "Start echo_server.hs and execute:"
  putStrLn "  echo \"cookie monster\""
  putStrLn ""
