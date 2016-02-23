{-# OPTIONS -XOverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

import Network.AMQP
import qualified Network.Freddy as Freddy
import GHC.Generics (Generic)
--import Data.ByteString.Lazy.Char8 (ByteString)
import Data.Aeson (ToJSON, encode)

data EchoRequest = EchoRequest {
  message :: String
} deriving (Generic, Show)

instance ToJSON EchoRequest

--responseCallback :: Int -> (Message, Envelope) -> IO ()
responseCallback nr deliverWithResponse body = do
  putStrLn "got response"
  if nr == 100 then
    putStrLn "done"
  else
    rEcho "hehe" nr deliverWithResponse

rEcho body nr deliverWithResponse = do
  let request = EchoRequest { message = body }
  deliverWithResponse "haskell" (encode request) (responseCallback (nr + 1) deliverWithResponse)

echo :: String -> Int -> IO ()
echo body nr = do
  (_, deliverWithResponse) <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
  rEcho body nr deliverWithResponse

done msg = do
  putStrLn "got msg"

main = do
  putStrLn "Start echo_server.hs and execute:"
  putStrLn "  echo \"cookie monster\""
  putStrLn ""

  --(_, deliverWithResponse) <- Freddy.connect "127.0.0.1" "/" "guest" "guest"
  --let req = EchoRequest { message = "adsf" }
  --deliverWithResponse "haskell" (encode req) done

-- perfecto
-- https://www.snip2code.com/Snippet/765832/Sending-and-receiving-messages-using-rab/
