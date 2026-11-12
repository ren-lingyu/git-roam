{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Commit (CommitMetadata (..), CommitIdentity (..), CommitDate (..), decodeCommitMetadata, readCommitMetadata) where

import Control.Monad (foldM, (>=>))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment, readStoredObject)
import GitRoam.ObjectId
import GitRoam.Protocol.Objects (ObjectProblem (..))

data CommitDate = CommitDate
    { dateTimestamp :: Integer
    , dateOffset :: BS.ByteString
    }
    deriving (Eq, Show)
data CommitIdentity = CommitIdentity
    { identityName :: BS.ByteString
    , identityEmail :: BS.ByteString
    , identityDate :: CommitDate
    }
    deriving (Eq, Show)
data CommitMetadata = CommitMetadata
    { metadataTree :: ObjectId
    , metadataParents :: [ObjectId]
    , metadataAuthor :: CommitIdentity
    , metadataCommitter :: CommitIdentity
    , metadataSubject :: BS.ByteString
    , metadataMessage :: BS.ByteString
    }
    deriving (Eq, Show)

-- Only tips are requested, deduplicated by OID, in a single scoped batch process.
-- Raw bytes are not transcoded, even when an encoding header is present.
readCommitMetadata :: Git IO -> FilePath -> ObjectFormat -> [(String, Maybe String)] -> [ObjectId] -> IO (Map.Map ObjectId (Either ObjectProblem CommitMetadata))
readCommitMetadata _ _ _ _ [] = pure Map.empty
readCommitMetadata git directory format environment tips = do
    let unique = Map.keys (Map.fromList [(oid, ()) | oid <- tips])
    outcome <- withGitBatch git (GitInvocation directory ["--no-replace-objects", "cat-file", "--batch"] BS.empty (environment ++ readOnlyEnvironment)) $ \scoped ->
        mapM
            ( \oid -> do
                result <- readStoredObject scoped directory environment oid
                pure (oid, result >>= decode)
            )
            unique
    pure $ case outcome of
        Left problem -> Map.fromList [(oid, Left (ObjectReadFailure (BSC.pack (show problem)))) | oid <- unique]
        Right values -> Map.fromList values
  where
    decode (kind, body)
        | kind /= "commit" = Left (WrongObjectType kind)
        | otherwise = either (Left . ObjectReadFailure . BSC.pack) Right (decodeCommitMetadata format body)

decodeCommitMetadata :: ObjectFormat -> BS.ByteString -> Either String CommitMetadata
decodeCommitMetadata format bytes = do
    let (headerBytes, rest) = BSC.breakSubstring "\n\n" bytes
    if BS.null rest then Left "Commit has no header terminator" else pure ()
    headers <- reverse <$> foldM header [] (BSC.split '\n' headerBytes)
    tree <- case headers of
        ("tree", [value]) : _ -> parseObjectId format value
        _ -> Left "Commit has no initial tree header"
    _ <- required "tree" headers
    parents <- mapM (scalar >=> parseObjectId format) [values | ("parent", values) <- headers]
    author <- required "author" headers >>= identity
    committer <- required "committer" headers >>= identity
    let message = BS.drop 2 rest
        firstLine = BS.takeWhile (/= 10) message
        subject = maybe firstLine id (BS.stripSuffix "\r" firstLine)
    pure (CommitMetadata tree parents author committer subject message)
  where
    -- Continuations belong to the preceding header, including opaque signatures.
    header records row
        | BS.isPrefixOf " " row = case records of
            (key, values) : more -> Right ((key, row : values) : more)
            [] -> Left "Commit has an orphan header continuation"
        | otherwise = case BSC.break (== ' ') row of
            (key, value) | not (BS.null key), BS.all (\byte -> byte > 32 && byte < 127) key, not (BS.null value), not (BS.elem 0 value) -> Right ((key, [BS.drop 1 value]) : records)
            _ -> Left "Malformed commit header"
    scalar [value] = Right value
    scalar _ = Left "Unexpected continuation in commit metadata header"
    required key headers = case [values | (name, values) <- headers, name == key] of
        [values] -> scalar values
        _ -> Left ("Missing or repeated commit " ++ BSC.unpack key ++ " header")
    identity value = do
        let (prefix, afterOpen) = BSC.breakEnd (== '<') value
            (email, suffix) = BSC.break (== '>') afterOpen
        name <- maybe (Left "Invalid commit identity name") Right (BS.stripSuffix " <" prefix)
        date <- maybe (Left "Invalid commit identity email") Right (BS.stripPrefix "> " suffix)
        if BS.any (`elem` [0, 10, 13, 60, 62]) (name <> email) then Left "Invalid bytes in commit identity" else pure ()
        parsed <- case BSC.split ' ' date of
            [timestamp, offset] | validOffset offset -> do
                number <- case BSC.readInteger timestamp of
                    Just (n, trailing) | BS.null trailing, validTimestamp timestamp -> Right n
                    _ -> Left "Invalid commit timestamp"
                pure (CommitDate number offset)
            _ -> Left "Invalid commit date or offset"
        pure (CommitIdentity name email parsed)
    digit byte = byte >= 48 && byte <= 57
    validTimestamp value = let digits = if BS.isPrefixOf "-" value then BS.drop 1 value else value in not (BS.null digits) && BS.all digit digits
    validOffset value = BS.length value == 5 && BS.take 1 value `elem` ["+", "-"] && BS.all digit (BS.drop 1 value)
