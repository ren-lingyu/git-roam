{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Objects (decodeCommit, decodeTree, nativeHistorySource, readOnlyEnvironment) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Objects
import System.Exit (ExitCode (..))

-- Per-call policy: stored history, no lazy network fetch or optional locks.
readOnlyEnvironment :: [(String, Maybe String)]
readOnlyEnvironment =
    [ ("GIT_NO_LAZY_FETCH", Just "1")
    , ("GIT_OPTIONAL_LOCKS", Just "0")
    , ("GIT_GRAFT_FILE", Just "/dev/null")
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
                    body <- envelope oid expected (gitStdout result)
                    either (Left . ObjectReadFailure . BSC.pack) Right (decoder body)

    envelope oid expected bytes =
        let (header, afterHeader) = BSC.break (== '\n') bytes
         in if header == objectIdBytes oid <> " missing"
                then Left MissingObject
                else case BSC.words header of
                    [actual, kind, size]
                        | actual == objectIdBytes oid && not (BS.null afterHeader) ->
                            if kind /= expected
                                then Left (WrongObjectType kind)
                                else case BSC.readInteger size of
                                    Just (count, leftover)
                                        | BS.null leftover && count >= 0
                                        , let body = BS.drop 1 afterHeader
                                        , toInteger (BS.length body) == count + 1
                                        , BS.last body == 10 ->
                                            Right (BS.init body)
                                    _ -> Left (ObjectReadFailure "Invalid batch object size")
                    _ -> Left (ObjectReadFailure "Invalid batch object header")
