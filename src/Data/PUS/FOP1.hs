{-# LANGUAGE GeneralizedNewtypeDeriving
    , BangPatterns 
    , NoImplicitPrelude
    , TemplateHaskell
    , OverloadedStrings
    , GADTs
    , TypeFamilies
#-}
module Data.PUS.FOP1
  ( FOPState
  , initialFOPState
  , fopWaitFlag
  , fopLockoutFlag
  , fopRetransmitFlag
  , fopVS
  , fopWaitQueue
  , fopSentQueue
  , fopToBeRetransmitted
  , fopADout
  , fopBDout
  , fopBCout
  , fopNNR
  , fopT1Initial
  , fopTimeoutType
  , fopTransmissionLimit
  , fopTransmissionCount
  , fopSuspendState
  , fopSlidingWinWidth
  )
where

import           RIO

import           Control.Lens                   ( makeLenses )
--import           Control.Lens.Setter

--import qualified Data.ByteString.Lazy          as B

import           Data.PUS.TCTransferFrame
--import           Data.PUS.CLCW
--import           Data.PUS.Types
import           Data.PUS.Time



data TTType = TTAlert | TTSuspend
  deriving (Eq, Ord, Enum, Show, Read)

data FOPState = FOPState {
  _fopWaitFlag :: !Bool,
  _fopLockoutFlag :: !Bool,
  _fopRetransmitFlag :: !Bool,
  _fopVS :: !Word8,
  _fopWaitQueue :: ![EncodedTCFrame],
  _fopSentQueue :: ![EncodedTCFrame],
  _fopToBeRetransmitted :: !Bool,
  _fopADout :: !Bool,
  _fopBDout :: !Bool,
  _fopBCout :: !Bool,
  _fopNNR :: !Word8,
  _fopT1Initial :: TimeSpan,
  _fopTimeoutType :: !TTType,
  _fopTransmissionLimit :: !Int,
  _fopTransmissionCount :: !Int,
  _fopSuspendState :: !Int,
  _fopSlidingWinWidth :: !Word8
  } deriving (Show, Read)

makeLenses ''FOPState


initialFOPState :: FOPState
initialFOPState = FOPState { _fopWaitFlag          = False
                           , _fopLockoutFlag       = False
                           , _fopRetransmitFlag    = False
                           , _fopVS                = 0
                           , _fopWaitQueue         = []
                           , _fopSentQueue         = []
                           , _fopToBeRetransmitted = False
                           , _fopADout             = False
                           , _fopBDout             = False
                           , _fopBCout             = False
                           , _fopNNR               = 0
                           , _fopT1Initial         = toTimeSpan $ mkTimeSpan Seconds 5
                           , _fopTimeoutType       = TTAlert
                           , _fopTransmissionLimit = 5
                           , _fopTransmissionCount = 0
                           , _fopSuspendState      = 0
                           , _fopSlidingWinWidth   = 10
                           }


_checkSlidingWinWidth :: Word8 -> Bool
_checkSlidingWinWidth w = (2 < w) && (w < 254) && even w


-- | S1
data Active
-- | S2
data RetransmitWithoutWait
-- | S3
data RetransmitWithWait
-- | S4
data InitialisingWithoutBC
-- | S5
data InitialisingWithBC
-- | S6
data Initial



class FOPMachine m where
  type State m :: * -> *
  initial :: m (State m Initial)
  -- | first, transitions from Initial
  e23 :: State m Initial -> m (State m Active)
  e31 :: State m Initial -> m (State m Active)
  e24 :: State m Initial -> m (State m InitialisingWithoutBC)
  e34 :: State m Initial -> m (State m InitialisingWithoutBC)
  e32 :: State m Initial -> m (State m RetransmitWithoutWait)
  e33 :: State m Initial -> m (State m RetransmitWithWait)
  e25 :: State m Initial -> m (State m InitialisingWithBC)
  e27 :: State m Initial -> m (State m InitialisingWithBC)
  -- | transitions from S1
  e8 :: E8State m -> m (State m RetransmitWithoutWait)
  e10 :: E10State m -> m (State m RetransmitWithoutWait)
  s1Exception :: State m Active -> m (State m Initial)
  -- | transitions from S2 
  e9 :: E9State m -> m (State m RetransmitWithWait)
  e11 :: E9State m -> m (State m RetransmitWithWait)
  e2 :: E2State m -> m (State m Active)
  e6 :: E6State m -> m (State m Active)
  e29 :: E29State m -> m (State m Initial)
  s2Exception :: State m RetransmitWithoutWait -> m (State m Initial)
  -- | transitions from S3



data E9State m = E9ActiveState (State m Active)
      | E9RetransmitWithoutWait (State m RetransmitWithoutWait)

data E29State m =
  E29ActiveState (State m Active)
  | E29RetransmitWithoutWait (State m RetransmitWithoutWait)
  | E29RetransmitWithWait (State m RetransmitWithWait)
  | E29InitialisingWithoutBC (State m InitialisingWithoutBC)
  | E29InitialisingWithBC (State m InitialisingWithBC)


data E2State m = 
  E2RetransmitWithoutWait (State m RetransmitWithoutWait)
  | E2RetransmitWithWait (State m RetransmitWithWait)

data E6State m = 
    E6RetransmitWithoutWait (State m RetransmitWithoutWait)
    | E6RetransmitWithWait (State m RetransmitWithWait)

data E8State m =
  E8Active (State m Active)
  | E8RetransmitWithWait (State m RetransmitWithWait)

data E10State m =
    E10Active (State m Active)
    | E10RetransmitWithWait (State m RetransmitWithWait)