module Network.FreddySpec where

import Test.Hspec
import qualified Network.Freddy as Freddy

spec :: Spec
spec = do
  describe "Freddy" $
    describe "connect" $ do
      it "works" $ do
        5 `shouldBe` 5
