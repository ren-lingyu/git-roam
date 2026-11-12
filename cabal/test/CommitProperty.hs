{-# LANGUAGE OverloadedStrings #-}

module CommitProperty (commitTests) where

import BatchFixture (fixtureGit)
import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import Control.Monad (forM_, unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Inspect as Inspect
import GitRoam.Application.Status
import qualified GitRoam.Application.Validation as Validation
import GitRoam.Cli (CliResponse (..), statusResponse)
import GitRoam.Git
import GitRoam.Git.Commit
import qualified GitRoam.Git.Objects as Objects
import GitRoam.ObjectId
import GitRoam.Output
import GitRoam.Protocol.Identity (NodeId, nodeIdBytes)
import GitRoam.Protocol.Objects (ObjectProblem (..))
import qualified GitRoam.Protocol.Objects as Protocol
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

commitTests :: [(String, IO ())]
commitTests =
    [ ("commit metadata preserves bytes, continuation headers and parent order", parsing)
    , ("commit subject has explicit LF/CR rules and never changes message", subjects)
    , ("commit dates preserve signed seconds and raw offsets without overflow", dates)
    , ("commit metadata rejects malformed required headers independently of protocol", malformed)
    , ("commit reader rejects missing/wrong/malformed objects and process failures", readerFailures)
    , ("commit timestamps encode as integers in JSON and CBOR", wireDates)
    ]
        ++ [("commit property native tips and CLI " ++ backend ++ " " ++ show format, fixture backend format (nativeMetadata format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("commit partial results, cost isolation and races " ++ backend ++ " " ++ show format, fixture backend format (partialMetadata format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("native commit session observations and strict history " ++ backend ++ " " ++ show format, fixture backend format (sessionObservations format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("Status session failures preserve independent properties " ++ backend ++ " " ++ show format, fixture backend format (sessionStatus format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

query :: [NodeProperty] -> StatusQuery
query properties = NodeStatusQuery AllNodes (SelectedProperties (Set.fromList properties))

oidBytes :: ObjectFormat -> Char -> BS.ByteString
oidBytes format = BSC.replicate (objectIdLength format)

author, committer :: BS.ByteString
author = "Raw Author <author@example.invalid> 1762855200 +0800"
committer = "Other Person <other@example.invalid> 1762855201 -0530"

rawCommit :: BS.ByteString -> [BS.ByteString] -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
rawCommit tree parents who by extra message = "tree " <> tree <> "\n" <> BSC.unlines (map ("parent " <>) parents) <> "author " <> who <> "\ncommitter " <> by <> "\n" <> extra <> "\n" <> message

parsing :: IO ()
parsing = forM_ [Sha1, Sha256] $ \format -> do
    let tree = oidBytes format '1'
        parents = [oidBytes format '3', oidBytes format '2']
        who = BS.pack [255] <> " Name <" <> BS.pack [254] <> "@invalid> 1 -0000"
        msg = BS.pack [233, 255, 0] <> "\r\n\nbody\rno final LF"
        extra = "encoding ISO-8859-1\ngpgsig -----BEGIN SIGNATURE-----\n author fake\n parent not-a-parent\n \n -----END SIGNATURE-----\nmergetag opaque\n tree not-a-tree\n"
    value <- expectRight (decodeCommitMetadata format (rawCommit tree parents who committer extra msg))
    assertEqual tree (objectIdBytes (metadataTree value))
    assertEqual parents (map objectIdBytes (metadataParents value))
    assertEqual (BS.pack [255] <> " Name") (identityName (metadataAuthor value))
    assertEqual (BS.pack [254] <> "@invalid") (identityEmail (metadataAuthor value))
    assertEqual (CommitDate 1 "-0000") (identityDate (metadataAuthor value))
    assertEqual msg (metadataMessage value)
    assertEqual (BS.pack [233, 255, 0]) (metadataSubject value)
    assertEqual "Other Person" (identityName (metadataCommitter value))

subjects :: IO ()
subjects = forM_ [("", ""), ("title", "title"), ("title\n\nbody\n", "title"), ("\nbody", ""), ("one\r\ntwo\r\n", "one"), ("one\rtwo", "one\rtwo"), ("one\r\r\ntwo", "one\r"), ("\r", "")] $ \(message, subject) -> do
    value <- expectRight (decodeCommitMetadata Sha1 (rawCommit (oidBytes Sha1 '1') [] author committer "" message))
    assertEqual message (metadataMessage value)
    assertEqual subject (metadataSubject value)

dates :: IO ()
dates = forM_ ["0", "-1", "2147483648", "9223372036854775807", "18446744073709551616", "-9223372036854775809"] $ \timestamp ->
    forM_ ["+0800", "-0530", "+0000", "-0000"] $ \offset -> do
        value <- expectRight (decodeCommitMetadata Sha1 (rawCommit (oidBytes Sha1 '1') [] ("A <> " <> timestamp <> " " <> offset) committer "" ""))
        assertEqual (CommitDate (read (BSC.unpack timestamp)) offset) (identityDate (metadataAuthor value))

malformed :: IO ()
malformed = do
    let tree = oidBytes Sha1 '1'
        base = rawCommit tree [] author committer "" "message"
    forM_ ["", " orphan\n\nmessage", "tree " <> tree <> "\nauthor bad\n\n", rawCommit tree [] author committer ("tree " <> tree <> "\n") "", rawCommit tree [] author committer ("author " <> author <> "\n") "", rawCommit tree ["bad"] author committer "" "", rawCommit tree [] author committer "broken\n" "", rawCommit tree [] author committer " continuation\n" "", BS.takeWhile (/= 10) base] $ expectLeft . decodeCommitMetadata Sha1
    forM_ ["A <a> - +0000", "A <a> 1x +0000", "A <a> 1 0800", "A <a> 1 +00:00", "A <a> 1 +00x0", "A <a> 1 +00000", "A <a> 1  +0000", "A a 1 +0000", "A <a> 1 +0000 trailing"] $ \bad -> do
        let bytes = rawCommit tree [] bad committer "" ""
        expectLeft (decodeCommitMetadata Sha1 bytes)
        -- Metadata errors must not expand the protocol decoder's obligations.
        _ <- expectRight (Objects.decodeCommit Sha1 bytes)
        pure ()

readerFailures :: IO ()
readerFailures = do
    oid <- expectRight (parseObjectId Sha1 (oidBytes Sha1 '1'))
    let object = objectIdBytes oid
        fake result = Git (const (pure result))
        readOne git = readCommitMetadata git "/fixture" Sha1 [] [oid] >>= maybe (fail "Missing requested result") pure . Map.lookup oid . observedCommits
    missing <- readOne (fake (Right (GitResult ExitSuccess (object <> " missing\n") "")))
    assertEqual (Left MissingObject) missing
    wrong <- readOne (fake (Right (GitResult ExitSuccess (object <> " blob 1\nx\n") "")))
    assertEqual (Left (WrongObjectType "blob")) wrong
    forM_ [Right (GitResult ExitSuccess (object <> " commit 100\nx\n") ""), Right (GitResult (ExitFailure 1) "unreliable" "failed"), Left (GitTransportError "fixture"), Right (GitResult ExitSuccess (object <> " commit 1\nx\n") "")] $ \result -> readOne (fake result) >>= expectLeft
    calls <- newIORef (0 :: Int)
    let none = Git (\_ -> modifyIORef' calls (+ 1) >> fail "Unexpected empty metadata read")
    empty <- readCommitMetadata none "/fixture" Sha1 [] []
    assertEqual (CommitObservation Map.empty []) empty
    readIORef calls >>= assertEqual 0

wireDates :: IO ()
wireDates = do
    let huge = 18446744073709551616
    forM_ [huge, -huge, 0, 2147483648] $ \timestamp -> do
        let value = Number timestamp
        json <- expectRight (Aeson.eitherDecodeStrict' (encodeValue JsonFormat value) :: Either String Integer)
        assertEqual timestamp json
        (rest, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict (encodeValue CborFormat value)))
        assertEqual BL.empty rest
        case term of
            CBOR.TInt n -> assertEqual timestamp (toInteger n)
            CBOR.TInteger n -> assertEqual timestamp n
            _ -> fail "Timestamp is not a CBOR integer"

nativeMetadata :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeMetadata format git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    let a = "refs/heads/" <> nodeIdBytes nodeA
        b = "refs/heads/" <> nodeIdBytes nodeB
    rootTip <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack a] ""
    other <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack b] ""
    raw <- ok git repo ["cat-file", "commit", BSC.unpack rootTip] ""
    decoded <- expectRight (decodeCommitMetadata format raw)
    assertEqual [] (metadataParents decoded)
    let tree = objectIdBytes (metadataTree decoded)
        message = BS.pack [233, 255] <> " title\r\n\nbody\n"
        extra = "encoding ISO-8859-1\ngpgsig signature\n author fake\n parent ignored\n"
    content <- writeCommit git repo a (rawCommit tree [rootTip] author committer extra message)
    contentValue <- oneCommit git repo
    assertEqual [contentParent rootTip] (metadataParents contentValue)
    checkpoint <- writeCommit git repo a (rawCommit tree [content, other] author committer extra message)
    -- An intentionally unrelated .mailmap/config must not transform identities.
    BS.writeFile (parent </> "mailmap") "Mapped <mapped@invalid> Raw Author <author@example.invalid>\n"
    _ <- ok git repo ["config", "mailmap.file", parent </> "mailmap"] ""
    _ <- ok git repo ["config", "i18n.logOutputEncoding", "UTF-8"] ""
    calls <- newIORef []
    let traced = observeGit (\invocation -> modifyIORef' calls (++ [invocation])) git
    report <- queryStatus traced repo (NodeStatusQuery (SelectedNodes (Set.singleton nodeA)) (SelectedProperties (Set.singleton CommitProperty))) >>= expectRight
    assertEqual [] (reportDiagnostics report)
    value <- case report of
        NodesReport [row] [] -> do
            assertEqual NotRequested (statusTip row)
            assertEqual NotRequested (statusWorktrees row)
            assertEqual NotRequested (statusRemote row)
            case statusCommit row of Available result -> pure result; _ -> fail "Metadata unavailable"
        _ -> fail "Wrong metadata report"
    case statusValue report of
        Object [("nodes", Array [Object fields]), ("diagnostics", Array [])] -> assertEqual ["node", "commit"] (map fst fields)
        _ -> fail "Commit selection leaked dependency fields"
    assertEqual [content, other] (map objectIdBytes (metadataParents value))
    assertEqual "Raw Author" (identityName (metadataAuthor value))
    assertEqual (CommitDate 1762855200 "+0800") (identityDate (metadataAuthor value))
    assertEqual (CommitDate 1762855201 "-0530") (identityDate (metadataCommitter value))
    assertEqual message (metadataMessage value)
    assertEqual (BS.pack [233, 255] <> " title") (metadataSubject value)
    args <- readIORef calls
    assertEqual 1 (length [() | call <- args, "cat-file" `elem` gitArguments call])
    assertEqual [] [gitArguments call | call <- args, any (`elem` gitArguments call) ["status", "worktree", "rev-list", "fsck", "log"]]
    forM_ [JsonFormat, CborFormat] $ \wire -> do
        result <- cli executable repo wire ["-n", BSC.unpack (nodeIdBytes nodeA)]
        assertEqual ExitSuccess (gitExitCode result)
        assertEqual BS.empty (gitStderr result)
        let expected = encodeValue wire (statusValue report)
        assertEqual expected (gitStdout result)
        if wire == JsonFormat
            then do
                _ <- expectRight (Aeson.eitherDecodeStrict' expected :: Either String Aeson.Value)
                assertTrue "Invalid UTF-8 must have no replacement text" ("\"utf8\":null" `BS.isInfixOf` expected)
                assertTrue "Lost byte envelope" ("base64" `BS.isInfixOf` expected)
            else do
                (rest, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict expected))
                assertEqual BL.empty rest
                assertTrue "CBOR lost raw commit message" (contains message term)
    text <- runGit (nativeGit executable) (GitInvocation repo ["status", "-t", "node", "-p", "commit", "-n", BSC.unpack (nodeIdBytes nodeA)] "" []) >>= expectRight
    assertEqual ExitSuccess (gitExitCode text)
    assertEqual (Encoding.encodeUtf8 (renderStatus report)) (gitStdout text)
    assertTrue "Fixture must have a checkpoint" (checkpoint /= content)
  where
    contentParent = either error id . parseObjectId format
    oneCommit native directory = do
        report <- queryStatus native directory (NodeStatusQuery (SelectedNodes (Set.singleton nodeA)) (SelectedProperties (Set.singleton CommitProperty))) >>= expectRight
        case report of NodesReport [row] [] | Available value <- statusCommit row -> pure value; _ -> fail (show report)

partialMetadata :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
partialMetadata format git executable repo _ = do
    root git repo nodeA
    root git repo nodeB
    let branch node = "refs/heads/" <> nodeIdBytes node
    tip <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (branch nodeA)] ""
    raw <- ok git repo ["cat-file", "commit", BSC.unpack tip] ""
    rootValue <- expectRight (decodeCommitMetadata format raw)
    let tree = objectIdBytes (metadataTree rootValue)
        missingParent = oidBytes format 'f'
    _ <- writeCommit git repo (branch nodeA) (rawCommit tree [missingParent] author committer "" "orphan ancestor")
    bad <- writeCommit git repo (branch nodeB) (rawCommit tree [] "broken identity" committer "" "malformed metadata")
    calls <- newIORef []
    let traced = observeGit (\invocation -> modifyIORef' calls (++ [gitArguments invocation])) git
    report <- queryStatus traced repo (query [TipProperty, CommitProperty]) >>= expectRight
    case report of
        NodesReport [a, b] issues -> do
            case statusCommit a of Available value -> assertEqual [missingParent] (map objectIdBytes (metadataParents value)); _ -> fail "Missing ancestor must not block tip metadata"
            assertEqual Unavailable (statusCommit b)
            oid <- expectRight (parseObjectId format bad)
            assertEqual (Available oid) (statusTip b)
            assertEqual [("commit_unavailable", Just nodeB, Just CommitProperty)] [(statusCode item, diagnosticNode item, diagnosticProperty item) | item <- issues]
        _ -> fail (show report)
    readIORef calls >>= \args -> assertEqual 1 (length [() | call <- args, "cat-file" `elem` call])
    forM_ [JsonFormat, CborFormat] $ \wire -> do
        result <- cli executable repo wire []
        assertEqual (ExitFailure 3) (gitExitCode result)
        only <- queryStatus git repo (query [CommitProperty]) >>= expectRight
        assertEqual (encodeValue wire (statusValue only)) (gitStdout result)
        forM_ (BSC.lines (gitStderr result)) $ \line -> do
            _ <- expectRight (Aeson.eitherDecodeStrict' line :: Either String Aeson.Value)
            pure ()
    -- Neither tip-only nor defaults start the metadata batch or history validator.
    forM_ [query [TipProperty], NodeStatusQuery AllNodes DefaultProperties] $ \request -> do
        modifyIORef' calls (const [])
        result <- queryStatus traced repo request >>= expectRight
        assertEqual [] (reportDiagnostics result)
        readIORef calls >>= \args -> assertEqual [] [call | call <- args, any (`elem` call) ["cat-file", "rev-list", "fsck", "status"]]
    strict <- Inspect.inspectState git repo [] Nothing
    case strict of
        Left _ -> pure ()
        Right complete -> assertTrue "Invalid state reported valid" (not (null (Inspect.reportProblems complete)))
    -- Scoped native batching and one-shot adapters must make the same tip requests.
    inputs <- newIORef []
    let adapter = Git $ \invocation -> do
            if "cat-file" `elem` gitArguments invocation then modifyIORef' inputs (++ [gitInput invocation]) else pure ()
            runGit git invocation
    _ <- queryStatus adapter repo (query [CommitProperty]) >>= expectRight
    requested <- readIORef inputs
    assertEqual 2 (length requested)
    assertTrue "Ancestor was read" (all (/= missingParent <> "\n") requested)
    counter <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            result <- runGit git invocation
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    modifyIORef' counter (+ 1)
                    n <- readIORef counter
                    pure $ if n == 2 then fmap (\r -> r{gitStdout = BSC.unlines (drop 1 (BSC.lines (gitStdout r)))}) result else result
                else pure result
    race <- queryStatus racing repo (query [CommitProperty]) >>= expectRight
    assertTrue "Lost ref race diagnostic" (any ((== "observation_changed") . statusCode) (reportDiagnostics race))
    -- Equal tips share the metadata read, even across different Node identities.
    good <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (branch nodeA)] ""
    _ <- ok git repo ["update-ref", BSC.unpack (branch nodeB), BSC.unpack good] ""
    modifyIORef' inputs (const [])
    shared <- queryStatus adapter repo (query [CommitProperty]) >>= expectRight
    assertEqual [] (reportDiagnostics shared)
    readIORef inputs >>= assertEqual [good <> "\n"]
    -- A symbolic alias is not silently reported as an ordinary Node tip.
    _ <- ok git repo ["symbolic-ref", BSC.unpack (branch nodeB), BSC.unpack (branch nodeA)] ""
    symbolic <- queryStatus git repo (query [CommitProperty]) >>= expectRight
    case symbolic of
        NodesReport [_, b] issues -> do
            assertEqual Unavailable (statusCommit b)
            let symbolicIssues = [item | item <- issues, statusCode item == "symbolic_node_branch"]
            assertEqual [Nothing] (map diagnosticProperty symbolicIssues)
            assertEqual [Just nodeB] (map diagnosticNode symbolicIssues)
        _ -> fail (show symbolic)

sessionObservations :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
sessionObservations format git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    a <- nodeTip git repo nodeA
    b <- nodeTip git repo nodeB
    bytes <- ok git repo ["cat-file", "commit", BSC.unpack (objectIdBytes a)] ""
    metadata <- expectRight (decodeCommitMetadata format bytes)
    extra <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack (objectIdBytes (metadataTree metadata)), "-p", BSC.unpack (objectIdBytes a), "-m", "additional stored tip"] ""
    c <- expectRight (parseObjectId format extra)
    let requested = Set.fromList [a, b, c]
        order = Set.toAscList requested
    forM_ ["commit-echo", "commit-missing", "commit-truncated", "commit-first-exit", "commit-bad-oid", "commit-bad-size", "commit-bad-terminator", "commit-nonzero", "commit-trailing"] $ \scenario -> do
        faulty <- fixtureGit scenario parent
        observed <- readCommitMetadata faulty repo format [] [a, b, c, a]
        assertEqual requested (Map.keysSet (observedCommits observed))
        let values = Map.elems (observedCommits observed)
            available = length [() | Right _ <- values]
            problems = commitSessionProblems observed
        case scenario of
            "commit-echo" -> do
                assertEqual 3 available
                assertEqual [] problems
            "commit-missing" -> do
                assertEqual 2 available
                case order of
                    [_, middle, _] -> assertEqual (Just (Left MissingObject)) (Map.lookup middle (observedCommits observed))
                    _ -> fail "Expected three unique fixture tips"
                assertEqual [] problems
            "commit-nonzero" -> do
                assertEqual 3 available
                case problems of [BatchProcessExited _] -> pure (); _ -> fail (show problems)
            "commit-trailing" -> do
                assertEqual 0 available
                case problems of [BatchCompletionUncertain _] -> pure (); _ -> fail (show problems)
            _ -> do
                assertEqual 1 available
                case values of Right _ : _ -> pure (); _ -> fail "Verified first response was discarded"
                case problems of BatchRequestFailed _ : _ -> pure (); _ -> fail (show problems)
        starts <- lines <$> readFile (parent </> "requests.starts")
        assertEqual ["start"] starts
        requests <- BSC.lines <$> BS.readFile (parent </> "requests")
        let count = case scenario of "commit-first-exit" -> 1; "commit-truncated" -> 2; "commit-bad-oid" -> 2; "commit-bad-size" -> 2; "commit-bad-terminator" -> 2; _ -> 3
        assertEqual (map objectIdBytes (take count order)) requests
    startup <- readCommitMetadata (nativeGit (parent </> "absent-executable")) repo format [] [a, b, a]
    assertEqual (Set.fromList [a, b]) (Map.keysSet (observedCommits startup))
    assertEqual 0 (length [() | Right _ <- Map.elems (observedCommits startup)])
    assertEqual 1 (length (commitSessionProblems startup))
    -- No callback result may cross the strict history boundary after exit 7.
    faulty <- fixtureGit "commit-nonzero" parent
    reached <- newIORef False
    history <- Objects.withHistorySource faulty repo format [] $ \source -> do
        objects <- mapM (Protocol.loadCommit source) [a, b]
        mapM_ expectRight objects
        modifyIORef' reached (const True)
    readIORef reached >>= assertEqual True
    expectLeft history
    Inspect.inspectState faulty repo [] Nothing >>= expectLeft
    Validation.validateCandidate faulty repo (Map.fromList [(nodeA, a), (nodeB, b)]) >>= expectLeft

sessionStatus :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
sessionStatus _ git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    a <- nodeTip git repo nodeA
    manual git repo (parent </> "deployed") nodeA
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/remotes/origin/" <> nodeIdBytes nodeA), BSC.unpack (objectIdBytes a)] ""
    let request = query [TipProperty, CommitProperty, WorktreesProperty, RemoteProperty]
    forM_ [("commit-nonzero", 2), ("commit-truncated", 1), ("commit-trailing", 0)] $ \(scenario, available) -> do
        faulty <- fixtureGit scenario parent
        report <- queryStatus faulty repo request >>= expectRight
        values <- case report of NodesReport rows _ -> pure rows; _ -> fail (show report)
        assertEqual 2 (length values)
        assertEqual available (length [() | row <- values, Available _ <- [statusCommit row]])
        forM_ values $ \row -> do
            case statusTip row of Available _ -> pure (); _ -> fail "Commit session lost independent tip"
            case statusWorktrees row of Available _ -> pure (); _ -> fail "Commit session lost worktree registration"
            case statusRemote row of Available _ -> pure (); _ -> fail "Commit session lost remote observation"
        case values of
            first : _ -> do
                case statusWorktrees first of Available [_] -> pure (); _ -> fail "Lost registered worktree"
                case statusRemote first of Available remote -> assertEqual (Just [("refs/remotes/origin/" <> nodeIdBytes nodeA, a)]) (remoteRefs remote); _ -> fail "Lost remote tracking ref"
            _ -> fail "Missing Node records"
        let issues = reportDiagnostics report
            sessionIssues = [item | item <- issues, statusCode item == "commit_session_incomplete"]
            objectIssues = [item | item <- issues, statusCode item == "commit_unavailable"]
        assertEqual [Nothing] (map diagnosticNode sessionIssues)
        assertEqual [Just CommitProperty] (map diagnosticProperty sessionIssues)
        assertEqual (2 - available) (length objectIssues)
        forM_ objectIssues $ \item -> do
            assertTrue "Object diagnostic lacks Node" (diagnosticNode item /= Nothing)
            assertEqual (Just CommitProperty) (diagnosticProperty item)
        forM_ [JsonFormat, CborFormat] $ \wire -> do
            let response = statusResponse wire report
            assertEqual (ExitFailure 3) (responseExitCode response)
            assertEqual Text.empty (responseStderr response)
            assertEqual (encodeValue wire (statusValue report)) (responseStdout response)
            if wire == JsonFormat
                then do
                    _ <- expectRight (Aeson.eitherDecodeStrict' (responseStdout response) :: Either String Aeson.Value)
                    assertTrue "Missing structured session diagnostic" ("commit_session_incomplete" `BS.isInfixOf` responseStdout response)
                else do
                    (rest, _) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict (responseStdout response)))
                    assertEqual BL.empty rest
        let text = statusResponse TextFormat report
        assertEqual (ExitFailure 3) (responseExitCode text)
        assertTrue "Text omitted session error" ("Raw commit metadata session did not finish successfully" `Text.isInfixOf` responseStderr text)
    -- The fixture would corrupt a batch, but the default never launches one.
    faulty <- fixtureGit "commit-trailing" parent
    defaults <- queryStatus faulty repo (NodeStatusQuery AllNodes DefaultProperties) >>= expectRight
    assertEqual [] (reportDiagnostics defaults)
    BS.readFile (parent </> "requests.starts") >>= assertEqual BS.empty

nodeTip :: Git IO -> FilePath -> NodeId -> IO ObjectId
nodeTip git repo node = do
    bytes <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack ("refs/heads/" <> nodeIdBytes node)] ""
    format <- if BS.length bytes == 40 then pure Sha1 else pure Sha256
    expectRight (parseObjectId format bytes)

writeCommit :: Git IO -> FilePath -> BS.ByteString -> BS.ByteString -> IO BS.ByteString
writeCommit git repo ref bytes = do
    oid <- BSC.init <$> ok git repo ["hash-object", "--literally", "-t", "commit", "-w", "--stdin"] bytes
    _ <- ok git repo ["update-ref", BSC.unpack ref, BSC.unpack oid] ""
    pure oid

cli :: FilePath -> FilePath -> OutputFormat -> [String] -> IO GitResult
cli executable repo wire selectors = do
    let name = if wire == JsonFormat then "json" else "cbor"
    result <- runGit (nativeGit executable) (GitInvocation repo (["--format", name, "status", "-t", "node", "-p", "commit"] ++ selectors) "" [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]) >>= expectRight
    unless (gitExitCode result `elem` [ExitSuccess, ExitFailure 3]) (fail (show result))
    pure result

contains :: BS.ByteString -> CBOR.Term -> Bool
contains raw term = case term of
    CBOR.TBytes bytes -> bytes == raw
    CBOR.TMap pairs -> any (contains raw . snd) pairs
    CBOR.TList values -> any (contains raw) values
    _ -> False
