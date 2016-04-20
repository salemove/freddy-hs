module Network.Freddy.CorrelationIdGenerator (CorrelationId, generateCorrelationId) where

import System.Random (randomIO)
import qualified Data.UUID as UUID
import Data.UUID (UUID)
import Data.Text (Text)

type CorrelationId = Text

generateCorrelationId :: IO CorrelationId
generateCorrelationId = do
  uuid <- newUUID
  return $ UUID.toText uuid

newUUID :: IO UUID
newUUID = randomIO
