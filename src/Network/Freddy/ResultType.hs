{-# LANGUAGE OverloadedStrings #-}
module Network.Freddy.ResultType (ResultType (..), serializeResultType, fromText) where

import Data.Text (Text, pack)

data ResultType = Success | Error deriving (Eq)

serializeResultType :: ResultType -> Text
serializeResultType resType = case resType of
  Success -> pack "success"
  Error -> pack "error"

fromText :: Text -> ResultType
fromText text = case text of
   "success" -> Success
   _ -> Error
