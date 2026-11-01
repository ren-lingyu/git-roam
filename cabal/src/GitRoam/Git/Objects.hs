{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Objects (decodeCommit, decodeTree, nativeHistorySource, readOnlyEnvironment, checkStoredConnectivity, peelStoredCommit) where

import Control.Monad (foldM)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Objects
import System.Exit (ExitCode (..))

-- Per-call policy: stored history, no lazy network fetch or optional locks.
readOnlyEnvironment :: [(String, Maybe String)]
readOnlyEnvironment =
    [ ("GIT_NO_LAZY_FETCH", Just "1")
    , ("GIT_OPTIONAL_LOCKS", Just "0")
    ]

decodeCommit :: ObjectFormat -> BS.ByteString -> Either String CommitObject
decodeCommit format bytes = do
    let (headers, separator) = BSC.breakSubstring "\n\n" bytes
        rows = BSC.lines headers
    if BS.null separator then Left "Commit has no header terminator" else pure ()
    content <- case rows of
        first : _ | Just value <- BS.stripPrefix "tree " first -> parseObjectId format value
        _ -> Left "Commit has no initial tree header"
    if length (filter (BS.isPrefixOf "tree ") rows) /= 1
        then Left "Commit has multiple tree headers"
        else pure ()
    parents <- mapM (parseObjectId format) [value | row <- rows, Just value <- [BS.stripPrefix "parent " row]]
    pure (CommitObject content parents)

decodeTree :: ObjectFormat -> BS.ByteString -> Either String [TreeEntry]
decodeTree format = go
  where
    rawLength = objectIdLength format `div` 2
    go remaining
        | BS.null remaining = Right []
        | otherwise = do
            let (modeBytes, afterMode) = BSC.break (== ' ') remaining
            mode <- case modeBytes of
                "40000" -> Right Directory
                "040000" -> Right Directory
                "100644" -> Right RegularFile
                "100755" -> Right ExecutableFile
                "120000" -> Right SymbolicLink
                "160000" -> Right Gitlink
                _ -> Left "Unsupported tree mode"
            if BS.null afterMode then Left "Tree entry has no name" else pure ()
            let (name, afterName) = BS.break (== 0) (BS.drop 1 afterMode)
            if BS.null afterName then Left "Tree entry has no object separator" else pure ()
            let (raw, rest) = BS.splitAt rawLength (BS.drop 1 afterName)
            if BS.length raw /= rawLength then Left "Truncated binary tree object ID" else pure ()
            oid <- parseObjectId format (BS.concatMap hexadecimal raw)
            (TreeEntry name mode oid :) <$> go rest
    hexadecimal byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48 + n else 87 + n

nativeHistorySource ::
    (Monad m) =>
    Git m -> FilePath -> ObjectFormat -> [(String, Maybe String)] -> HistorySource m
nativeHistorySource git directory format environment =
    HistorySource
        (readStored "commit" (decodeCommit format))
        (readStored "tree" (decodeTree format))
  where
    readStored expected decoder oid = do
        outcome <-
            runGit git $
                GitInvocation
                    directory
                    ["--no-replace-objects", "cat-file", "--batch"]
                    (objectIdBytes oid <> "\n")
                    (environment ++ readOnlyEnvironment)
        pure $ case outcome of
            Left problem -> Left (ObjectReadFailure (BSC.pack (show problem)))
            Right result
                | gitExitCode result /= ExitSuccess -> Left (ObjectReadFailure (gitStderr result))
                | otherwise -> do
                    (kind, body) <- envelope oid (gitStdout result)
                    if kind /= expected then Left (WrongObjectType kind) else pure ()
                    either (Left . ObjectReadFailure . BSC.pack) Right (decoder body)

envelope :: ObjectId -> BS.ByteString -> Either ObjectProblem (BS.ByteString, BS.ByteString)
envelope oid bytes =
    let (header, afterHeader) = BSC.break (== '\n') bytes
     in if header == objectIdBytes oid <> " missing"
            then Left MissingObject
            else case BSC.words header of
                [actual, kind, size]
                    | actual == objectIdBytes oid && not (BS.null afterHeader) ->
                        case BSC.readInteger size of
                            Just (count, leftover)
                                | BS.null leftover && count >= 0
                                , let body = BS.drop 1 afterHeader
                                , toInteger (BS.length body) == count + 1
                                , BS.last body == 10 ->
                                    Right (kind, BS.init body)
                            _ -> Left (ObjectReadFailure "Invalid batch object size")
                _ -> Left (ObjectReadFailure "Invalid batch object header")

-- Only raw OIDs reach cat-file. Grafts, shallow boundaries and replacement refs
-- must not redefine stored edges. Gitlinks belong to a different object database.
-- Blob contents are not loaded: one batch-check verifies their type/existence.
checkStoredConnectivity :: (Monad m) => Git m -> FilePath -> [(String, Maybe String)] -> HistorySource m -> [ObjectId] -> m (Either (ObjectId, ObjectProblem) [ObjectId])
checkStoredConnectivity git directory environment source tips = runExceptT $ do
    (_, trees) <- commits Set.empty Set.empty tips
    (_, blobs) <- treeObjects Set.empty Set.empty (Set.toList trees)
    if Set.null blobs
        then pure []
        else do
            let oids = Set.toList blobs
            result <- batchMetadata git directory environment oids
            foldM checkBlob [] (zip oids result)
  where
    load loader oid = ExceptT (fmap (either (Left . (,) oid) Right) (loader oid))
    commits seen trees [] = pure (seen, trees)
    commits seen trees (oid : rest)
        | Set.member oid seen = commits seen trees rest
        | otherwise = do
            object <- load (loadCommit source) oid
            commits (Set.insert oid seen) (Set.insert (commitTree object) trees) (commitParents object ++ rest)
    treeObjects seen blobs [] = pure (seen, blobs)
    treeObjects seen blobs (oid : rest)
        | Set.member oid seen = treeObjects seen blobs rest
        | otherwise = do
            entries <- load (loadTree source) oid
            let children = [entryObject e | e <- entries, entryMode e == Directory]
                payloads = [entryObject e | e <- entries, entryMode e `elem` [RegularFile, ExecutableFile, SymbolicLink]]
            treeObjects (Set.insert oid seen) (Set.union blobs (Set.fromList payloads)) (children ++ rest)
    checkBlob missing (oid, kind) = case kind of
        Nothing -> pure (missing ++ [oid])
        Just "blob" -> pure missing
        Just other -> throwE (oid, WrongObjectType other)

batchMetadata :: (Monad m) => Git m -> FilePath -> [(String, Maybe String)] -> [ObjectId] -> ExceptT (ObjectId, ObjectProblem) m [Maybe BS.ByteString]
batchMetadata _ _ _ [] = pure []
batchMetadata git directory environment oids@(first : _) = do
    outcome <- lift (runGit git (GitInvocation directory ["--no-replace-objects", "cat-file", "--batch-check=%(objectname) %(objecttype)"] (BSC.unlines (map objectIdBytes oids)) (environment ++ readOnlyEnvironment)))
    bytes <- case outcome of
        Left problem -> throwE (first, ObjectReadFailure (BSC.pack (show problem)))
        Right result | gitExitCode result == ExitSuccess -> pure (gitStdout result)
        Right result -> throwE (first, ObjectReadFailure (gitStderr result))
    let rows = BSC.lines bytes
    if length rows /= length oids then throwE (first, ObjectReadFailure "Invalid batch metadata count") else pure ()
    mapM decode (zip oids rows)
  where
    decode (oid, row) = case BSC.words row of
        [actual, kind] | actual == objectIdBytes oid -> pure (if kind == "missing" then Nothing else Just kind)
        _ -> throwE (oid, ObjectReadFailure "Invalid batch metadata response")

-- Annotated tags are peeled from their stored object headers, without invoking
-- revision traversal or parsing commit parents through Git's graft machinery.
peelStoredCommit :: (Monad m) => Git m -> FilePath -> ObjectFormat -> [(String, Maybe String)] -> ObjectId -> m (Either (ObjectId, ObjectProblem) ObjectId)
peelStoredCommit git directory format environment start = runExceptT (go Set.empty start)
  where
    go seen oid
        | Set.member oid seen = throwE (oid, ObjectReadFailure "Cyclic tag chain")
        | otherwise = do
            kinds <- batchMetadata git directory environment [oid]
            case kinds of
                [Just "commit"] -> pure oid
                [Just "tag"] -> do
                    outcome <- lift (runGit git (GitInvocation directory ["--no-replace-objects", "cat-file", "--batch"] (objectIdBytes oid <> "\n") (environment ++ readOnlyEnvironment)))
                    body <- case outcome of
                        Left problem -> throwE (oid, ObjectReadFailure (BSC.pack (show problem)))
                        Right result | gitExitCode result == ExitSuccess -> do
                            (_, bytes) <- either (throwE . (,) oid) pure (envelope oid (gitStdout result))
                            pure bytes
                        Right result -> throwE (oid, ObjectReadFailure (gitStderr result))
                    target <- case BSC.lines body of
                        row : _
                            | Just bytes <- BS.stripPrefix "object " row ->
                                either (const (throwE (oid, ObjectReadFailure "Invalid tag target"))) pure (parseObjectId format bytes)
                        _ -> throwE (oid, ObjectReadFailure "Tag has no target")
                    go (Set.insert oid seen) target
                [Nothing] -> throwE (oid, MissingObject)
                [Just kind] -> throwE (oid, WrongObjectType kind)
                _ -> throwE (oid, ObjectReadFailure "Invalid tag metadata")
