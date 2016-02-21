{-# OPTIONS -XOverloadedStrings #-}

import qualified Network.Freddy as Freddy
import Data.ByteString.Lazy.Char8 (ByteString)

processMessage :: Freddy.Request -> IO ()
processMessage (Freddy.Request body replyWith failWith) = replyWith body

main = do
  fConnection <- Freddy.connect "127.0.0.1" "/" "guest" "guest"

  Freddy.respondTo fConnection "EchoServer" processMessage

  putStrLn "Service started!"
  putStrLn ""
  putStrLn "Sample usage using ruby:"
  putStrLn "  freddy.deliver_with_response 'EchoServer', message: 'hello there'"
  putStrLn ""