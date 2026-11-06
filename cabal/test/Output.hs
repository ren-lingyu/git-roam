{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Codec.CBOR.Decoding as CBOR
import qualified Codec.CBOR.Read as CBOR
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as Text
import GitRoam.Application.Create (CreationResult (..), createdBundlePath)
import GitRoam.ObjectId (ObjectFormat (Sha1), parseObjectId)
import GitRoam.Output
import GitRoam.Protocol.Identity (parseNodeId)
import GitRoam.Worktree.Paths (decodePath, encodePath)
import System.FilePath ((</>))
import TestSupport

main :: IO ()
main =
    runTests
        [ ("text output remains unchanged", textResult)
        , ("JSON output preserves arbitrary filesystem bytes", jsonResult)
        , ("CBOR output preserves arbitrary filesystem bytes", cborResult)
        ]

sample :: FilePath -> IO CreationResult
sample path = do
    node <- expectRight (parseNodeId "11111111-1111-4111-8111-111111111111")
    oid <- expectRight (parseObjectId Sha1 (BS.replicate 40 97))
    pure (CreationResult node oid path)

textResult :: IO ()
textResult = do
    result <- sample "/tmp/notes"
    actual <- renderCreation TextFormat result
    let expected =
            BS.concat
                [ "node 11111111-1111-4111-8111-111111111111\n"
                , "root aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
                , "worktree \"/tmp/notes\"\n"
                , "bundle \"/tmp/notes/11111111-1111-4111-8111-111111111111\"\n"
                ]
    assertEqual expected actual

jsonResult :: IO ()
jsonResult = do
    -- A non-UTF-8 POSIX byte must not be silently changed to U+FFFD.
    let raw = BS.pack [47, 116, 109, 112, 47, 255]
    path <- decodePath raw
    result <- sample path
    actual <- renderCreation JsonFormat result
    assertEqual 10 (BS.last actual)
    value <- expectRight (Aeson.eitherDecodeStrict' actual :: Either String Aeson.Value)
    let pathValue bytes =
            Aeson.object
                [ "utf8" Aeson..= (Nothing :: Maybe Text.Text)
                , "base64" Aeson..= (Text.pack (showAscii (Base64.encode bytes)))
                ]
        expected =
            Aeson.object
                [ "node" Aeson..= ("11111111-1111-4111-8111-111111111111" :: Text.Text)
                , "root" Aeson..= ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" :: Text.Text)
                , "worktree" Aeson..= pathValue raw
                , "bundle" Aeson..= pathValue (raw <> "/11111111-1111-4111-8111-111111111111")
                ]
    assertEqual expected value
    pathBytes <- encodePath path
    assertEqual raw pathBytes
  where
    showAscii = map (toEnum . fromEnum) . BS.unpack

cborResult :: IO ()
cborResult = do
    let raw = BS.pack [47, 116, 109, 112, 47, 255]
    path <- decodePath raw
    result <- sample path
    bytes <- renderCreation CborFormat result
    parsed <-
        expectRight
            ( case CBOR.deserialiseFromBytes decoder (BL.fromStrict bytes) of
                Left err -> Left (show err)
                Right (leftover, fields) | BL.null leftover -> Right fields
                Right _ -> Left "Trailing CBOR data"
            )
    assertEqual
        ( "11111111-1111-4111-8111-111111111111"
        , "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        , raw
        , raw <> "/11111111-1111-4111-8111-111111111111"
        )
        parsed
    assertEqual (path </> "11111111-1111-4111-8111-111111111111") (createdBundlePath result)
  where
    decoder = do
        count <- CBOR.decodeMapLen
        a <- CBOR.decodeString
        node <- CBOR.decodeString
        b <- CBOR.decodeString
        root <- CBOR.decodeString
        c <- CBOR.decodeString
        worktree <- CBOR.decodeBytes
        d <- CBOR.decodeString
        bundle <- CBOR.decodeBytes
        if count == 4 && [a, b, c, d] == ["node", "root", "worktree", "bundle"]
            then pure (node, root, worktree, bundle)
            else fail "Invalid creation CBOR keys"
