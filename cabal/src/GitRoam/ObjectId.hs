{-# LANGUAGE OverloadedStrings #-}

module GitRoam.ObjectId (
    ObjectFormat (..),
    ObjectId,
    objectIdBytes,
    objectIdLength,
    parseObjectFormat,
    parseObjectId,
) where

import qualified Data.ByteString as BS

data ObjectFormat = Sha1 | Sha256
    deriving (Eq, Show)

newtype ObjectId = ObjectId BS.ByteString
    deriving (Eq, Ord, Show)

objectIdBytes :: ObjectId -> BS.ByteString
objectIdBytes (ObjectId bytes) = bytes

objectIdLength :: ObjectFormat -> Int
objectIdLength Sha1 = 40
objectIdLength Sha256 = 64

parseObjectFormat :: BS.ByteString -> Either String ObjectFormat
parseObjectFormat "sha1" = Right Sha1
parseObjectFormat "sha256" = Right Sha256
parseObjectFormat _ = Left "Unsupported Git object format"

parseObjectId :: ObjectFormat -> BS.ByteString -> Either String ObjectId
parseObjectId format bytes
    | BS.length bytes /= objectIdLength format = Left "Invalid Git object ID length"
    | not (BS.all hexadecimal bytes) = Left "Expected a lowercase hexadecimal object ID"
    | BS.all (== 48) bytes = Left "The null object ID is not a stored object ID"
    | otherwise = Right (ObjectId bytes)
  where
    hexadecimal byte = (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
