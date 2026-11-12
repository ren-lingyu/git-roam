{-# LANGUAGE OverloadedStrings #-}

module WireAssertions (decodeWire, field, diagnosticAt) where

import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text.Encoding as Text
import TestSupport

-- Decode actual bytes, normalizing CBOR byte strings to the lossless JSON view.
decodeWire :: String -> BS.ByteString -> IO Aeson.Value
decodeWire "json" bytes = do
    assertTrue "Expected a nonempty JSON report" (not (BS.null bytes))
    assertEqual 10 (BS.last bytes)
    expectRight (Aeson.eitherDecodeStrict' bytes)
decodeWire "cbor" bytes = do
    (remaining, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict bytes))
    assertEqual BL.empty remaining
    convert term
  where
    convert (CBOR.TMap values) = Aeson.object <$> mapM pair values
    convert (CBOR.TList values) = Aeson.toJSON <$> mapM convert values
    convert (CBOR.TString value) = pure (Aeson.String value)
    convert (CBOR.TBytes value) = pure $ Aeson.object ["utf8" Aeson..= (either (const Nothing) Just (Text.decodeUtf8' value) :: Maybe Text), "base64" Aeson..= Text.decodeUtf8 (Base64.encode value)]
    convert (CBOR.TBool value) = pure (Aeson.Bool value)
    convert CBOR.TNull = pure Aeson.Null
    convert (CBOR.TInt value) = pure (Aeson.toJSON value)
    convert (CBOR.TInteger value) = pure (Aeson.toJSON value)
    convert value = fail ("Unexpected CBOR term: " ++ show value)
    pair (CBOR.TString key, value) = (,) (Key.fromText key) <$> convert value
    pair value = fail (show value)
decodeWire encoding _ = fail ("Unknown wire format: " ++ encoding)

field :: String -> Aeson.Value -> IO Aeson.Value
field name value = case Aeson.fromJSON value :: Aeson.Result (Map.Map String Aeson.Value) of
    Aeson.Success fields -> maybe (fail ("Missing field " ++ name)) pure (Map.lookup name fields)
    Aeson.Error message -> fail message

diagnosticAt :: Int -> Aeson.Value -> IO Aeson.Value
diagnosticAt index value = do
    diagnostics <- field "diagnostics" value
    case Aeson.fromJSON diagnostics :: Aeson.Result [Aeson.Value] of
        Aeson.Success values | index < length values -> pure (values !! index)
        _ -> fail "Missing diagnostic"
