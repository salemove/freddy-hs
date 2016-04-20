{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy.Request (
  Request (..),
  timeoutInMicroseconds,
  expirationInMs,
  newReq
) where

import Data.Text (Text, pack)
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

timeoutInMicroseconds :: Request -> Int
timeoutInMicroseconds = (*) 1000 . timeoutInMs

expirationInMs :: Request -> Maybe Text
expirationInMs request =
  if deleteOnTimeout request
    then Just . pack . show . timeoutInMs $ request
    else Nothing

newReq :: Request
newReq = def
