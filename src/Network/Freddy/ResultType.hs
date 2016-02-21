module Network.Freddy.ResultType (ResultType (..), serializeResultType) where

data ResultType = Success | Error

serializeResultType resType = case resType of
  Success -> "success"
  Error -> "error"
