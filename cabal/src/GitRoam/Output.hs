{-# LANGUAGE OverloadedStrings #-}

{- | Render creation results without imposing a text encoding on filesystem paths.
The format is a presentation decision; Node creation itself is format-agnostic.
-}
module GitRoam.Output (OutputFormat (..), renderCreation) where

import qualified Codec.CBOR.Encoding as CBOR
import qualified Codec.CBOR.Write as CBOR
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Create (CreationResult (..), createdBundlePath)
import GitRoam.ObjectId (objectIdBytes)
import GitRoam.Protocol.Identity (nodeIdBytes)
import GitRoam.Worktree.Paths (encodePath)

data OutputFormat = TextFormat | JsonFormat | CborFormat
    deriving (Eq, Show)

{- | The text encoding is intentionally unchanged for existing CLI consumers.
JSON adds a readable UTF-8 view and an authoritative Base64 byte view.
CBOR uses byte strings directly, so no Unicode conversion is needed.
-}
renderCreation :: OutputFormat -> CreationResult -> IO BS.ByteString
renderCreation format result = case format of
    TextFormat ->
        pure $
            Encoding.encodeUtf8 $
                Text.unlines
                    [ "node " <> identity
                    , "root " <> root
                    , "worktree " <> Text.pack (show (createdPath result))
                    , "bundle " <> Text.pack (show (createdBundlePath result))
                    ]
    JsonFormat -> do
        (worktree, bundle) <- pathBytes
        pure $
            BL.toStrict
                ( Aeson.encode
                    ( Aeson.object
                        [ "node" Aeson..= identity
                        , "root" Aeson..= root
                        , "worktree" Aeson..= jsonPath worktree
                        , "bundle" Aeson..= jsonPath bundle
                        ]
                    )
                )
                <> "\n"
    CborFormat -> do
        (worktree, bundle) <- pathBytes
        pure $
            CBOR.toStrictByteString $
                CBOR.encodeMapLen 4
                    <> CBOR.encodeString "node"
                    <> CBOR.encodeString identity
                    <> CBOR.encodeString "root"
                    <> CBOR.encodeString root
                    <> CBOR.encodeString "worktree"
                    <> CBOR.encodeBytes worktree
                    <> CBOR.encodeString "bundle"
                    <> CBOR.encodeBytes bundle
  where
    identity = Encoding.decodeUtf8 (nodeIdBytes (createdNode result))
    root = Encoding.decodeUtf8 (objectIdBytes (createdRoot result))
    pathBytes = (,) <$> encodePath (createdPath result) <*> encodePath (createdBundlePath result)

-- | Path bytes are the source of truth; UTF-8 is only a convenience field.
jsonPath :: BS.ByteString -> Aeson.Value
jsonPath bytes =
    Aeson.object
        [ "utf8" Aeson..= (either (const Nothing) Just (Encoding.decodeUtf8' bytes) :: Maybe Text)
        , "base64" Aeson..= Encoding.decodeUtf8 (Base64.encode bytes)
        ]
