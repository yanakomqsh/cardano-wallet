{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
module Cardano.Wallet.Write.Tx.Gen
    ( genDatumHash
    )
    where

import Prelude

import Cardano.Wallet.Write.Tx
    ( DatumHash, datumHashFromBytes )
import Data.Maybe
    ( fromMaybe )
import Test.QuickCheck
    ( Gen, arbitrary, vectorOf )

import qualified Data.ByteString as BS

genDatumHash :: Gen DatumHash
genDatumHash =
    fromMaybe (error "genDatumHash should always generate valid hashes")
    . datumHashFromBytes
    . BS.pack <$> vectorOf 32 arbitrary
