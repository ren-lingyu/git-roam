{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Protocol.Identity (NodeId, nodeIdBytes, parseNodeId) where

import qualified Data.ByteString as BS

-- The permanent label accepts canonical UUID text, not only newly generated v4s.
newtype NodeId = NodeId BS.ByteString
    deriving (Eq, Ord, Show)

nodeIdBytes :: NodeId -> BS.ByteString
nodeIdBytes (NodeId bytes) = bytes

parseNodeId :: BS.ByteString -> Either String NodeId
parseNodeId bytes
    | BS.length bytes == 36 && and (zipWith valid [0 :: Int ..] (BS.unpack bytes)) =
        Right (NodeId bytes)
    | otherwise = Left "Expected a canonical lowercase hyphenated UUID"
  where
    valid position byte
        | position `elem` [8, 13, 18, 23] = byte == 45
        | otherwise = (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
