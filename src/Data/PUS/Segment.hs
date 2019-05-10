{-# LANGUAGE OverloadedStrings
    , BangPatterns
    , GeneralizedNewtypeDeriving
    , DeriveGeneric
    , RecordWildCards
    , TemplateHaskell
    , NoImplicitPrelude
#-}
module Data.PUS.Segment
    ( TCSegment
    , mkTCSegments
    , encodeSegments
    , SegmentHeader(..)
    --, SegmentTrailer(..)
    , SegFlags(..)
    , EncodedSegment(..)
    , segMapID
    , segFlags
    , segData
    , segHeader
    --, segTrailer
    , segMaxDataLen
    , isControlCommand
    , isControlSelFixed
    , isControlSelProgrammable
    , segHeaderBuilder
    , segHeaderParser
    , segBuilder
    , segParser

    , encSegSegment
    , encSegFlag
    , encSeqSegNr
    , encSeqRequest

    )
where


import           RIO                     hiding ( Builder )
import qualified RIO.ByteString                as B
import           RIO.List.Partial               ( head
                                                , tail
                                                )

import           Control.Lens                   ( makeLenses )

import           ByteString.StrictBuilder
import           Data.Bits
import           Data.Attoparsec.ByteString     ( Parser )
import qualified Data.Attoparsec.ByteString    as A
import           Data.List.NonEmpty             ( NonEmpty(..)
                                                , (<|)
                                                )
import qualified Data.List.NonEmpty            as L

import           Data.PUS.Types
import           Data.PUS.TCRequest

import           General.Chunks



segMaxDataLen :: Int
segMaxDataLen = 248


data SegFlags = SegmentFirst
    | SegmentContinue
    | SegmentLast
    | SegmentStandalone
    deriving (Ord, Eq, Enum, Show, Read)

data SegmentHeader = SegmentHeader {
        _segFlags :: !SegFlags
        , _segMapID :: !MAPID
    } deriving (Eq, Show, Read)

makeLenses ''SegmentHeader


-- data SegmentTrailer = SegmentTrailer
--     deriving (Eq, Show, Read)

-- segTrailerLen :: SegmentTrailer -> Int
-- segTrailerLen _ = 0


data TCSegment = TCSegment {
    _segHeader :: !SegmentHeader
    , _segData :: !ByteString
    -- , _segTrailer :: Maybe SegmentTrailer
    } deriving (Eq, Show, Read)

makeLenses ''TCSegment

data EncodedSegment = EncodedSegment {
        _encSegSegment :: ByteString
        , _encSegFlag :: SegFlags
        , _encSeqSegNr :: Word32
        , _encSeqRequest :: TCRequest
    }

makeLenses ''EncodedSegment


mkTCSegments :: MAPID -> ByteString -> NonEmpty TCSegment
mkTCSegments mapid payload
    | B.length payload > segMaxDataLen
    = let
          chnks = chunkedByBS segMaxDataLen payload
          go :: [ByteString] -> NonEmpty TCSegment
          go []  = undefined
          go [x] = L.fromList [TCSegment (SegmentHeader SegmentLast mapid) x]
          go (x : xs) =
              TCSegment (SegmentHeader SegmentContinue mapid) x <| go xs
          firstSeg = head chnks
          segments = TCSegment (SegmentHeader SegmentFirst mapid) firstSeg
              <| go (tail chnks)
      in
          segments
    | otherwise
    = TCSegment (SegmentHeader SegmentStandalone mapid) payload :| []


encodeSegments :: TCRequest -> NonEmpty TCSegment -> NonEmpty EncodedSegment
encodeSegments req segments = L.zipWith f segments (L.fromList [1..])
    where
        f segment i =
            let encSeg = builderBytes $ segBuilder segment
            in
            EncodedSegment encSeg (segment ^. segHeader . segFlags) i req


data SegIDGroup1 = SegmentContDummy
       | SegmentContSelectFixed
       | SegmentContSelectProgrammable
       | SegmentContLoadFixedToProgrammable
       deriving (Ord, Eq, Enum, Show)

data SegIDGroup2= SegmentContSetLAC
       deriving (Ord, Eq, Enum, Show)

data SegIDGroup3 = SegmentContChangeBlockA
      | SegmentContChangeBlockB
      deriving (Ord, Eq, Enum, Show)


-- data ControlSegment = Group1 {
--         segID1 :: SegIDGroup1
--     }
--     | Group2 {
--         segID2 :: SegIDGroup2,
--         segLAC :: LacCounter
--     }
--     | Group3 {
--         segID3 :: SegIDGroup3,
--         segAddress :: Word8,
--         segKeyData :: B.ByteString
--     }
--     deriving (Show)



isControlCommand :: SegmentHeader -> Bool
isControlCommand (SegmentHeader fl mapid) =
    (fl == SegmentStandalone) && (mapid == mapIDControl)

isControlSelFixed :: ByteString -> Bool
isControlSelFixed segdata
    | B.length segdata > 2
    = (segdata `B.index` 0) == 0xFF && (segdata `B.index` 1) == 0x05
    | otherwise
    = False

isControlSelProgrammable :: ByteString -> Bool
isControlSelProgrammable segdata
    | B.length segdata > 2
    = (segdata `B.index` 0) == 0xFF && (segdata `B.index` 1) == 0x06
    | otherwise
    = False


segHeaderBuilder :: SegmentHeader -> Builder
segHeaderBuilder (SegmentHeader flags mapid) = word8 result
  where
    conv SegmentFirst      = 0x40
    conv SegmentContinue   = 0x00
    conv SegmentLast       = 0x80
    conv SegmentStandalone = 0xC0

    result = conv flags .|. getMAPID mapid

segHeaderParser :: Parser SegmentHeader
segHeaderParser = do
    val <- A.anyWord8
    let flags = case val .&. 0xC0 of
            0x40 -> SegmentFirst
            0x00 -> SegmentContinue
            0x80 -> SegmentLast
            0xC0 -> SegmentStandalone
            _    -> SegmentStandalone
        mapid = mkMAPID val
    pure (SegmentHeader flags mapid)


segBuilder :: TCSegment -> Builder
segBuilder (TCSegment hdr pl) = segHeaderBuilder hdr <> bytes pl

segParser :: Parser TCSegment
segParser = do
    hdr <- segHeaderParser
    pl  <- A.takeByteString
    pure (TCSegment hdr pl)
