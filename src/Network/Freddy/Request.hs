{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy.Request (Request (..), newReq) where

import Data.Text (Text)
import Data.Default (Default, def)
import Data.ByteString.Lazy.Char8 (ByteString)
import qualified Data.ByteString.Lazy.Char8 as BS

data Request = Request {
  queueName :: Text,
  body :: ByteString,
  timeoutInMs :: Int,
  deleteOnTimeout :: Bool
} deriving (Show)

instance Default Request where
  def = Request {
    queueName = "localhost",
    body = BS.empty,
    timeoutInMs = 3000,
    deleteOnTimeout = True
  }

newReq :: Request
newReq = def
