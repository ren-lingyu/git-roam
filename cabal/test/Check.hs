{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import BatchFixture
import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import Control.Monad (forM_, unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified GitRoam.Application.Check as Check
import qualified GitRoam.Application.Create as Create
import qualified GitRoam.Application.Deploy as Deploy
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Validation
import GitRoam.Cli (CliResponse (..), Command (..), checkResponse, parseCommand)
import GitRoam.Git
import qualified GitRoam.Git.Refs as Refs
import GitRoam.ObjectId
import GitRoam.Output
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (doesPathExist, removeFile)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runBatchFixture $
        runTests $
            [("Check parser and typed failure classification", classification)]
                ++ [ (backend ++ "/" ++ show format ++ ": " ++ name, fixture backend format (test format))
                   | backend <- ["files", "reftable"]
                   , format <- [Sha1, Sha256]
                   , (name, test) <-
                        [ ("whole-state scope, costs and wire reports", scope)
                        , ("native violations and retained initial refs", violations)
                        , ("ref failures and invalid-to-inconclusive precedence", observationFailures)
                        , ("strict raw framing and object conclusions", objectFailures)
                        , ("native batch startup/completion evidence", sessions)
                        , ("empty state and documented enumeration boundary", emptyState)
                        , ("occupied names and transaction symref races", occupied)
                        ]
                   ]

type Scenario = ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()

query :: Git IO -> FilePath -> IO Check.CheckReport
query git repo = Check.checkManagedState git repo >>= expectRight

expectConclusion :: Check.CheckConclusion -> Check.CheckReport -> IO ()
expectConclusion expected report = do
    assertEqual expected (Check.checkConclusion report)
    forM_ [False, True] $ \showRefs -> forM_ [TextFormat, JsonFormat, CborFormat] $ \format -> do
        let response = checkResponse format showRefs report
        assertEqual (case expected of Check.Valid -> ExitSuccess; Check.Invalid -> ExitFailure 1; Check.Inconclusive -> ExitFailure 3) (responseExitCode response)
        assertEqual "" (responseStderr response)
        let body = responseStdout response
        case format of
            TextFormat -> assertTrue "Text conclusion missing" ((case expected of Check.Valid -> "valid\n"; Check.Invalid -> "invalid\n"; Check.Inconclusive -> "inconclusive\n") `BS.isPrefixOf` body)
            JsonFormat -> do
                value <- expectRight (Aeson.eitherDecodeStrict' body :: Either String (Map.Map String Aeson.Value))
                assertEqual (if showRefs then ["diagnostics", "refs", "valid"] else ["diagnostics", "valid"]) (Map.keys value)
                assertEqual (Just (case expected of Check.Valid -> Aeson.Bool True; Check.Invalid -> Aeson.Bool False; Check.Inconclusive -> Aeson.Null)) (Map.lookup "valid" value)
                let refsValue = maybe Aeson.Null (Aeson.toJSON . Map.fromList . map (\(node, oid) -> ("refs/heads/" ++ BSC.unpack (nodeIdBytes node), BSC.unpack (objectIdBytes oid))) . Map.toAscList) (Check.checkRefs report)
                assertEqual (if showRefs then Just refsValue else Nothing) (Map.lookup "refs" value)
            CborFormat -> do
                (remaining, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict body))
                assertEqual BL.empty remaining
                case term of
                    CBOR.TMap fields -> do
                        assertEqual (if showRefs then 3 else 2) (length fields)
                        assertEqual (Just (case expected of Check.Valid -> CBOR.TBool True; Check.Invalid -> CBOR.TBool False; Check.Inconclusive -> CBOR.TNull)) (lookup (CBOR.TString "valid") fields)
                        let refsValue = maybe CBOR.TNull (CBOR.TMap . map (\(node, oid) -> (CBOR.TString ("refs/heads/" <> nodeText node), CBOR.TString (oidText oid))) . Map.toAscList) (Check.checkRefs report)
                        assertEqual (if showRefs then Just refsValue else Nothing) (lookup (CBOR.TString "refs") fields)
                    _ -> fail (show term)

classification :: IO ()
classification = do
    assertEqual (Right (CheckManagedState False)) (parseCommand ["check"])
    assertEqual (Right (CheckManagedState True)) (parseCommand ["check", "--show-refs"])
    forM_ [["check", "--node", BSC.unpack (nodeIdBytes nodeA)], ["check", "--show-refs", "--show-refs"], ["check", "--show-refs=true"], ["check", "--format", "json"], ["check", "unknown"]] (expectLeft . parseCommand)
    let oid = either error id (parseObjectId Sha1 (BS.replicate 40 97))
    forM_ [MissingObject, WrongObjectType "blob", MalformedObject "bad bytes"] $ \problem -> assertEqual Check.Invalid (Check.conclusionFor (HistoryFailure (ObjectUnavailable oid problem)))
    forM_ [ObjectReadFailure "missing", IncompleteHistory "malformed"] $ \problem -> assertEqual Check.Inconclusive (Check.conclusionFor (HistoryFailure (ObjectUnavailable oid problem)))
    assertEqual Check.Inconclusive (Check.conclusionFor (CandidateStateInvalid [UnknownNodeTip nodeA oid]))
    assertEqual Check.Inconclusive (Check.conclusionFor ReferencesChanged)
    assertEqual Check.Invalid (Check.conclusionFor (SymbolicNodeBranch nodeA "refs/heads/other"))
    -- Lookup failures and noisy output must never imply an available name.
    forM_ [GitResult (ExitFailure 1) "" "failure", GitResult (ExitFailure 128) "" "failure", GitResult ExitSuccess "unexpected" "", GitResult ExitSuccess "" "warning"] $ \value ->
        Refs.refExists (Git (const (pure (Right value)))) "." [] "refs/heads/name" >>= expectLeft

scope :: Scenario
scope format git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    initial <- loadManagedState git repo >>= expectRight
    let expected = managedRefs initial
        nodePath = parent </> "node"
        ordinaryPath = parent </> "ordinary"
        bare = parent </> "bare.git"
    empty <- BSC.init <$> ok git repo ["mktree"] ""
    unrelated <- commit git repo empty []
    _ <- ok git repo ["update-ref", "refs/heads/ordinary", BSC.unpack unrelated] ""
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/remotes/origin/" <> nodeIdBytes nodeA), BSC.unpack unrelated] ""
    _ <- ok git repo ["update-ref", "refs/tags/unrelated", BSC.unpack unrelated] ""
    manual git repo nodePath nodeA
    _ <- ok git repo ["worktree", "add", "--", ordinaryPath, "ordinary"] ""
    BS.writeFile (nodePath </> "untracked") "user data"
    BS.writeFile (nodePath </> ".gitignore") "ignored\n"
    BS.writeFile (nodePath </> "ignored") "ignored user data"
    backend <- BSC.init <$> ok git repo ["rev-parse", "--show-ref-format"] ""
    _ <- ok git repo ["clone", "--bare", "--ref-format=" ++ BSC.unpack backend, repo, bare] ""
    forM_ [repo, nodePath, ordinaryPath, bare] $ \directory -> do
        report <- query git directory
        expectConclusion Check.Valid report
        assertEqual (Just expected) (Check.checkRefs report)
    calls <- newIORef []
    let watched = observeGit (\call -> modifyIORef' calls (gitArguments call :)) git
    report <- query watched repo
    arguments <- readIORef calls
    assertEqual 2 (length (filter (elem "for-each-ref") arguments))
    assertTrue "Check performed unrelated observation work" (all (\args -> not (any (`elem` args) ["worktree", "status", "config", "log", "show"])) arguments)
    let showValue = checkValue True report
        refs = Object [("refs/heads/" <> nodeText n, oidValue oid) | (n, oid) <- Map.toAscList expected]
    case showValue of Object fields -> assertEqual (Just refs) (lookup "refs" fields); _ -> fail "Not a map"
    readIORef calls >>= assertEqual arguments
    forM_ ["json", "cbor", "text"] $ \wire -> do
        result <- runGit (nativeGit executable) (GitInvocation nodePath ["--format", wire, "check", "--show-refs"] "" []) >>= expectRight
        assertEqual ExitSuccess (gitExitCode result)
        assertEqual "" (gitStderr result)
    rejected <- runGit (nativeGit executable) (GitInvocation repo ["check", "--node", BSC.unpack (nodeIdBytes nodeA)] "" []) >>= expectRight
    assertEqual (ExitFailure 2) (gitExitCode rejected)
    assertEqual "" (gitStdout rejected)
    outside <- runGit (nativeGit executable) (GitInvocation parent ["--format", "json", "check"] "" []) >>= expectRight
    assertEqual (ExitFailure 3) (gitExitCode outside)
    assertEqual "" (gitStdout outside)
    _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr outside) :: Either String Aeson.Value)
    forM_ (Map.elems expected) $ \oid -> assertEqual (objectIdLength format) (BS.length (objectIdBytes oid))

commit :: Git IO -> FilePath -> BS.ByteString -> [BS.ByteString] -> IO BS.ByteString
commit git repo tree parents = BSC.init <$> ok git repo (["commit-tree", BSC.unpack tree] ++ concatMap (\oid -> ["-p", BSC.unpack oid]) parents ++ ["-m", "Fixture"]) ""

tip :: Git IO -> FilePath -> NodeId -> IO BS.ByteString
tip git repo node = BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes node)] ""

set :: Git IO -> FilePath -> NodeId -> BS.ByteString -> IO ()
set git repo node oid = do
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes node), BSC.unpack oid] ""
    pure ()

violations :: Scenario
violations format git _ repo _ = do
    root git repo nodeA
    root git repo nodeB
    a <- tip git repo nodeA
    b <- tip git repo nodeB
    let oid = either error id . parseObjectId format
    set git repo nodeB a
    mismatch <- query git repo
    expectConclusion Check.Invalid mismatch
    assertEqual [Just nodeB] (map Check.checkNode (Check.checkDiagnostics mismatch))
    assertEqual ["identity_mismatch"] (map Check.checkCode (Check.checkDiagnostics mismatch))
    assertEqual (Just (Map.fromList [(nodeA, oid a), (nodeB, oid a)])) (Check.checkRefs mismatch)
    set git repo nodeB b
    _ <- ok git repo ["update-ref", "refs/heads/ordinary", BSC.unpack a] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), "refs/heads/ordinary"] ""
    symbolic <- query git repo
    expectConclusion Check.Invalid symbolic
    assertEqual ["symbolic_node_branch"] (map Check.checkCode (Check.checkDiagnostics symbolic))
    assertEqual (Just (Map.fromList [(nodeA, oid a), (nodeB, oid a)])) (Check.checkRefs symbolic)
    _ <- ok git repo ["symbolic-ref", "--delete", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB)] ""
    set git repo nodeB b
    at <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack a ++ "^{tree}"] ""
    bt <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack b ++ "^{tree}"] ""
    other <- commit git repo at []
    -- A different message guarantees a different Root even within one second.
    alternate <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack at, "-m", "Other Root"] ""
    unless (alternate /= a && other /= alternate) (fail "Root conflict fixture did not distinguish commits")
    bk <- commit git repo bt [b, alternate]
    set git repo nodeB bk
    _ <- validateCandidate git repo (Map.singleton nodeA (oid a)) >>= expectRight
    _ <- validateCandidate git repo (Map.singleton nodeB (oid bk)) >>= expectRight
    conflict <- query git repo
    expectConclusion Check.Invalid conflict
    assertEqual ["root_conflict"] (map Check.checkCode (Check.checkDiagnostics conflict))
    set git repo nodeB b
    let duplicateTree = "tree " <> at <> "\nauthor Fixture <fixture@example.invalid> 1000000000 +0000\ncommitter Fixture <fixture@example.invalid> 1000000000 +0000\ntree " <> at <> "\n\nMalformed protocol header\n"
    malformed <- BSC.init <$> ok git repo ["hash-object", "--literally", "-w", "-t", "commit", "--stdin"] duplicateTree
    set git repo nodeA malformed
    broken <- query git repo
    expectConclusion Check.Invalid broken
    assertEqual ["object_malformed"] (map Check.checkCode (Check.checkDiagnostics broken))
    set git repo nodeA a
    empty <- BSC.init <$> ok git repo ["mktree"] ""
    invalidTree <- commit git repo empty []
    set git repo nodeA invalidTree
    treeReport <- query git repo
    expectConclusion Check.Invalid treeReport
    assertEqual ["node_tree_invalid"] (map Check.checkCode (Check.checkDiagnostics treeReport))
    content <- commit git repo at [a]
    overlap <- commit git repo at [a, content]
    set git repo nodeA overlap
    contextReport <- query git repo
    expectConclusion Check.Invalid contextReport
    assertEqual ["context_overlap"] (map Check.checkCode (Check.checkDiagnostics contextReport))
    set git repo nodeA a
    marker <- BSC.init <$> ok git repo ["hash-object", "--stdin"] ""
    let text = BSC.unpack marker
    removeFile (repo </> ".git" </> "objects" </> take 2 text </> drop 2 text)
    absent <- query git repo
    expectConclusion Check.Invalid absent
    assertEqual ["objects_missing"] (map Check.checkCode (Check.checkDiagnostics absent))
    assertEqual [Just (oid marker)] (map Check.checkObject (Check.checkDiagnostics absent))

observationFailures :: Scenario
observationFailures _ git _ repo _ = do
    root git repo nodeA
    before <- loadManagedState git repo >>= expectRight
    forM_ (["transport", "command", "warning", "malformed"] :: [String]) $ \kind -> do
        let failing = Git $ \invocation -> do
                value <- runGit git invocation
                pure $
                    if "for-each-ref" `elem` gitArguments invocation
                        then case kind of
                            "transport" -> Left (GitTransportError "injected")
                            "command" -> fmap (\v -> v{gitExitCode = ExitFailure 128}) value
                            "warning" -> fmap (\v -> v{gitStderr = "warning"}) value
                            _ -> fmap (\v -> v{gitStdout = gitStdout v <> "broken\n"}) value
                        else value
        failed <- query failing repo
        expectConclusion Check.Inconclusive failed
        assertEqual Nothing (Check.checkRefs failed)
    counter <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            result <- runGit git invocation
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    n <- atomicModifyIORef' counter (\n -> (n + 1, n + 1))
                    pure (if n == 2 then fmap (\v -> v{gitStdout = ""}) result else result)
                else
                    if "--batch" `elem` gitArguments invocation
                        then pure (fmap (\v -> v{gitStdout = BS.takeWhile (/= 10) (gitInput invocation) <> " commit 3\nbad\n"}) result)
                        else pure result
    changed <- query racing repo
    expectConclusion Check.Inconclusive changed
    assertEqual ["observation_changed"] (map Check.checkCode (Check.checkDiagnostics changed))
    assertEqual (Just (managedRefs before)) (Check.checkRefs changed)
    assertEqual 2 =<< readIORef counter

objectFailures :: Scenario
objectFailures _ git _ repo _ = do
    root git repo nodeA
    initial <- loadManagedState git repo >>= expectRight
    forM_ (["missing", "truncated", "wrong", "unknown", "malformed", "metadata"] :: [String]) $ \kind -> do
        let failing = Git $ \invocation -> do
                result <- runGit git invocation
                let oid = BS.takeWhile (/= 10) (gitInput invocation)
                    body = case kind of
                        "missing" -> oid <> " missing\n"
                        "truncated" -> oid <> " missing"
                        "wrong" -> oid <> " blob 0\n\n"
                        "unknown" -> oid <> " invented 0\n\n"
                        _ -> oid <> " commit 3\nbad\n"
                pure $
                    if "--batch" `elem` gitArguments invocation && kind /= "metadata"
                        then fmap (\v -> v{gitStdout = body}) result
                        else
                            if any (isInfixOf "--batch-check=") (gitArguments invocation) && kind == "metadata"
                                then fmap (\v -> v{gitStdout = BS.init (gitStdout v)}) result
                                else result
        report <- query failing repo
        expectConclusion (if kind `elem` ["missing", "wrong", "malformed"] then Check.Invalid else Check.Inconclusive) report
        assertEqual (Just (managedRefs initial)) (Check.checkRefs report)

sessions :: Scenario
sessions _ git _ repo parent = do
    root git repo nodeA
    state <- loadManagedState git repo >>= expectRight
    forM_ ["early-exit", "commit-nonzero", "commit-malformed-nonzero", "commit-trailing"] $ \mode -> do
        failing <- fixtureGit mode parent
        report <- query failing repo
        expectConclusion Check.Inconclusive report
        assertEqual (Just (managedRefs state)) (Check.checkRefs report)
        assertEqual ["git_transport_failed"] (map Check.checkCode (Check.checkDiagnostics report))
        loadManagedState failing repo >>= expectLeft
        validateCandidate failing repo (managedRefs state) >>= expectLeft

emptyState :: Scenario
emptyState _ git _ repo _ = do
    report <- query git repo
    expectConclusion Check.Valid report
    assertEqual (Just Map.empty) (Check.checkRefs report)
    _ <- ok git repo ["symbolic-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), "refs/heads/missing"] ""
    Refs.refExists git repo [] ("refs/heads/" <> nodeIdBytes nodeA) >>= assertEqual (Right True)
    -- Explicit implementation boundary: native enumeration omits this ref.
    bounded <- query git repo
    expectConclusion Check.Valid bounded
    assertEqual (Just Map.empty) (Check.checkRefs bounded)

occupied :: Scenario
occupied _ git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    b <- tip git repo nodeB
    let ref = "refs/heads/" <> nodeIdBytes nodeB
        target = "refs/heads/missing-target"
        remote = "refs/remotes/origin/" <> nodeIdBytes nodeB
    _ <- ok git repo ["update-ref", BSC.unpack remote, BSC.unpack b] ""
    _ <- ok git repo ["update-ref", "-d", BSC.unpack ref] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack ref, BSC.unpack target] ""
    enable git executable repo
    before <- loadManagedState git repo >>= expectRight
    Create.createNodeWith (pure nodeB) executable git repo (parent </> "create") >>= refused "occupied"
    Deploy.deploy executable git repo (parent </> "deploy") Nothing >>= refused "occupied"
    after <- loadManagedState git repo >>= expectRight
    assertEqual (managedRefs before) (managedRefs after)
    ok git repo ["symbolic-ref", "--no-recurse", BSC.unpack ref] "" >>= assertEqual (target <> "\n")
    Refs.refExists git repo [] target >>= assertEqual (Right False)
    mapM_ (\path -> doesPathExist (parent </> path) >>= assertEqual False) ["create", "deploy"]
    _ <- ok git repo (ownHookBypass ++ ["symbolic-ref", "--delete", BSC.unpack ref]) ""
    let race node = Git $ \invocation -> do
            let candidateRef = "refs/heads/" <> nodeIdBytes node
            if "update-ref" `elem` gitArguments invocation && ("create " <> candidateRef <> " ") `BS.isInfixOf` gitInput invocation
                then do
                    _ <- ok git repo (ownHookBypass ++ ["symbolic-ref", BSC.unpack candidateRef, BSC.unpack target]) ""
                    pure ()
                else pure ()
            runGit git invocation
    Deploy.deploy executable (race nodeB) repo (parent </> "race") Nothing >>= expectLeft
    ok git repo ["symbolic-ref", "--no-recurse", BSC.unpack ref] "" >>= assertEqual (target <> "\n")
    Refs.refExists git repo [] target >>= assertEqual (Right False)
    let nodeC = either error id (parseNodeId "33333333-3333-4333-8333-333333333333")
    Create.createNodeWith (pure nodeC) executable (race nodeC) repo (parent </> "create-race") >>= expectLeft
    ok git repo ["symbolic-ref", "--no-recurse", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeC)] "" >>= assertEqual (target <> "\n")
    Refs.refExists git repo [] target >>= assertEqual (Right False)
  where
    refused fragment result = case result of
        Left problem -> assertTrue (show problem) (fragment `isInfixOf` show problem)
        Right _ -> fail "Occupied ref was overwritten"
