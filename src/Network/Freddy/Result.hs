module Network.Freddy.Result (Result (..)) where

data Result = Success | Error

instance Show Result where
  show res = case res of
    Success -> "success"
    Error -> "error"
