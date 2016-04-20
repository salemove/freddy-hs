{-# LANGUAGE OverloadedStrings #-}

import qualified Network.Freddy as Freddy
import Data.ByteString.Lazy.Char8 (ByteString)

processMessage :: Freddy.Delivery -> IO ()
processMessage (Freddy.Delivery body replyWith failWith) = replyWith body

main = do
  connection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"

  Freddy.respondTo connection "EchoServer" processMessage

  putStrLn "Service started!"
  putStrLn ""
  putStrLn "Sample usage using ruby:"
  putStrLn "  freddy.deliver_with_response 'EchoServer', message: 'hello there'"
  putStrLn ""
