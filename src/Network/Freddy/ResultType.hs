module Network.Freddy.ResultType (ResultType (..), serializeResultType) where

import Data.Text (Text, pack)

data ResultType = Success | Error

serializeResultType :: ResultType -> Text
serializeResultType resType = case resType of
  Success -> pack "success"
  Error -> pack "error"
