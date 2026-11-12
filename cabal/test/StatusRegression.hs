{-# LANGUAGE OverloadedStrings #-}

module StatusRegression (regressionTests) where

import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified GitRoam.Application.Deploy as Deploy
import GitRoam.Application.Status
import qualified GitRoam.Application.Validation as Validation
import GitRoam.Application.Worktree (planDeployment)
import GitRoam.Git
import qualified GitRoam.Git.Refs as Refs
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Directory (doesDirectoryExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

regressionTests :: [(String, IO ())]
regressionTests =
    [("partial upstream config preserves Node records and valueless evidence", configRecords)]
        ++ [("native upstream effective config semantics " ++ backend ++ " " ++ show format, fixture backend format upstreamSemantics) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("native upstream failures preserve base Status properties " ++ backend ++ " " ++ show format, fixture backend format (nativeIsolation format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("symbolic remote diagnostics respect selected local Nodes " ++ backend ++ " " ++ show format, fixture backend format symbolicSelection) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("adapter upstream fallback preserves ref-race and strict-read boundaries", fixture "files" Sha1 (adapterFailures Sha1))]

branchKey :: NodeId -> String -> String
branchKey node key = "branch." ++ BSC.unpack (nodeIdBytes node) ++ "." ++ key

localRef :: NodeId -> BS.ByteString
localRef node = "refs/heads/" <> nodeIdBytes node

remoteRef :: String -> NodeId -> BS.ByteString
remoteRef prefix node = "refs/remotes/" <> BSC.pack prefix <> "/" <> nodeIdBytes node

tipOf :: Git IO -> FilePath -> NodeId -> IO BS.ByteString
tipOf git repo node = BSC.init <$> ok git repo ["rev-parse", BSC.unpack (localRef node)] ""

setConfig :: Git IO -> FilePath -> NodeId -> String -> String -> IO ()
setConfig git repo node key value = do
    _ <- ok git repo ["config", branchKey node key, value] ""
    pure ()

report :: Git IO -> FilePath -> StatusQuery -> IO StatusReport
report git repo request = queryStatus git repo request >>= expectRight

defaultQuery :: StatusQuery
defaultQuery = NodeStatusQuery AllNodes DefaultProperties

selected :: [NodeId] -> StatusQuery
selected values = NodeStatusQuery (SelectedNodes (Set.fromList values)) (SelectedProperties (Set.singleton RemoteProperty))

nodeRows :: StatusReport -> IO [NodeStatus]
nodeRows (NodesReport values _) = pure values
nodeRows _ = fail "Expected Node status"

nodeRow :: NodeId -> StatusReport -> IO NodeStatus
nodeRow node result = do
    values <- nodeRows result
    case [value | value <- values, statusNode value == node] of
        [value] -> pure value
        _ -> fail "Expected one selected Node"

remoteOf :: NodeId -> StatusReport -> IO RemoteObservation
remoteOf node result = do
    value <- nodeRow node result
    case statusRemote value of Available remote -> pure remote; _ -> fail "Expected remote observation"

assertUpstream :: NodeId -> BS.ByteString -> BS.ByteString -> BS.ByteString -> StatusReport -> IO ()
assertUpstream node remote source ref result = do
    value <- remoteOf node result
    assertEqual (Available (Just (UpstreamObservation (Just remote) (Just source) (Just ref)))) (remoteUpstream value)

configRecords :: IO ()
configRecords = do
    let key node name = BSC.pack (branchKey node name)
        bytes = key nodeA "remote" <> "\nbackup\0" <> key nodeB "remote" <> "\0" <> key nodeA "remote" <> "\norigin\0" <> key nodeA "merge" <> "\nrefs/heads/main\0"
        observed = Refs.decodeUpstreamConfig bytes
    assertEqual (Just (Refs.UpstreamConfig ["backup", "origin"] ["refs/heads/main"])) (Map.lookup nodeA (Refs.observedConfigs observed))
    assertEqual [Just nodeB] (map Refs.configProblemNode (Refs.configProblems observed))
    let truncated = Refs.decodeUpstreamConfig (BS.init bytes)
    assertEqual Map.empty (Refs.observedConfigs truncated)
    assertEqual [Nothing] (map Refs.configProblemNode (Refs.configProblems truncated))
    let malformed = Refs.decodeUpstreamConfig (bytes <> "branch.11111111-1111-4111-8111-111111111111.unexpected\nx\0")
    assertEqual (Map.lookup nodeA (Refs.observedConfigs observed)) (Map.lookup nodeA (Refs.observedConfigs malformed))
    assertTrue "Malformed Node config lost its identity" (Just nodeA `elem` map Refs.configProblemNode (Refs.configProblems malformed))

upstreamSemantics :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
upstreamSemantics git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    none <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics none)
    remoteOf nodeA none >>= assertEqual (RemoteObservation (Available Nothing) (Just []))
    -- Remote-only is a normal default query, not an ambiguous upstream.
    setConfig git repo nodeA "remote" "origin"
    remoteOnly <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics remoteOnly)
    remoteOf nodeA remoteOnly >>= assertEqual (RemoteObservation (Available Nothing) (Just []))
    successfulDefault executable repo
    a <- tipOf git repo nodeA
    forM_ ["origin", "backup"] $ \name -> do
        _ <- ok git repo ["config", "remote." ++ name ++ ".fetch", "+refs/heads/*:refs/remotes/" ++ name ++ "/*"] ""
        _ <- ok git repo ["update-ref", BSC.unpack (remoteRef name nodeA), BSC.unpack a] ""
        pure ()
    setConfig git repo nodeA "merge" (BSC.unpack (localRef nodeA))
    normal <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics normal)
    assertUpstream nodeA "origin" (localRef nodeA) (remoteRef "origin" nodeA) normal
    setConfig git repo nodeB "remote" "."
    setConfig git repo nodeB "merge" (BSC.unpack (localRef nodeB))
    local <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics local)
    assertUpstream nodeB "." (localRef nodeB) (localRef nodeB) local
    _ <- ok git repo ["config", "--unset-all", branchKey nodeA "remote"] ""
    forM_ ["backup", "origin"] $ \name -> do
        _ <- ok git repo ["config", "--add", branchKey nodeA "remote", name] ""
        pure ()
    repeated <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics repeated)
    assertUpstream nodeA "origin" (localRef nodeA) (remoteRef "origin" nodeA) repeated
    successfulDefault executable repo
    -- Earlier global values and later repository-local values are not peers.
    _ <- ok git repo ["config", "--file", parent </> "global-config", branchKey nodeA "remote", "backup"] ""
    layered <- report (withGitEnvironment [("GIT_CONFIG_GLOBAL", Just (parent </> "global-config"))] git) repo defaultQuery
    assertEqual [] (reportDiagnostics layered)
    assertUpstream nodeA "origin" (localRef nodeA) (remoteRef "origin" nodeA) layered
    _ <- ok git repo ["config", "--add", branchKey nodeA "merge", "refs/heads/another"] ""
    multiple <- report git repo defaultQuery
    assertTrue "Multiple merge values were guessed" (any ((== "upstream_ambiguous") . statusCode) (reportDiagnostics multiple))
    remote <- remoteOf nodeA multiple
    case remoteUpstream remote of
        Available (Just value) -> do
            assertEqual (Just "origin") (upstreamRemote value)
            assertEqual Nothing (upstreamSource value)
        _ -> fail "Known upstream evidence was lost"
    _ <- ok git repo ["config", "--unset-all", branchKey nodeA "merge"] ""
    setConfig git repo nodeA "merge" "refs/heads/unmapped"
    _ <- ok git repo ["config", "--unset-all", branchKey nodeA "remote"] ""
    _ <- ok git repo ["config", "--unset-all", "remote.origin.fetch"] ""
    unresolved <- report git repo defaultQuery
    assertTrue "Unresolvable merge was treated as absence" (any ((== "upstream_unresolved") . statusCode) (reportDiagnostics unresolved))
    unresolvedRemote <- remoteOf nodeA unresolved
    case remoteUpstream unresolvedRemote of
        Available (Just value) -> assertEqual (Just "refs/heads/unmapped") (upstreamSource value)
        _ -> fail "Merge configuration was discarded"

prepareTracked :: Git IO -> FilePath -> IO ()
prepareTracked git repo = do
    root git repo nodeA
    root git repo nodeB
    a <- tipOf git repo nodeA
    b <- tipOf git repo nodeB
    _ <- ok git repo ["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"] ""
    forM_ [(nodeA, a), (nodeB, b)] $ \(node, oid) -> do
        _ <- ok git repo ["update-ref", BSC.unpack (remoteRef "origin" node), BSC.unpack oid] ""
        pure ()
    setConfig git repo nodeA "remote" "origin"
    setConfig git repo nodeA "merge" (BSC.unpack (localRef nodeA))

nativeIsolation :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeIsolation format git executable repo parent = do
    prepareTracked git repo
    manual git repo (parent </> "worktree") nodeA
    -- This is valid generic Git-config syntax but invalid for branch.remote.
    appendFile (repo </> ".git/config") ("\n[branch \"" ++ BSC.unpack (nodeIdBytes nodeB) ++ "\"]\n\tremote\n")
    basic <- Refs.readNodeRefs git repo [] format Refs.LocalAndRemoteNodes
    assertTrue "Plain ref enumeration failed" (Refs.observationComplete basic)
    combined <- Refs.readNodeRefs git repo [] format Refs.LocalAndRemoteUpstreams
    assertTrue "Pinned native Git did not expose the upstream failure" (not (Refs.observationComplete combined))
    tipOnly <- report git repo (NodeStatusQuery AllNodes (SelectedProperties (Set.singleton TipProperty)))
    assertEqual [] (reportDiagnostics tipOnly)
    nodeRows tipOnly >>= assertEqual [nodeA, nodeB] . map statusNode
    config <- Refs.readUpstreamConfig git repo []
    assertTrue "A's config disappeared" (Map.member nodeA (Refs.observedConfigs config))
    assertEqual [Just nodeB] (map Refs.configProblemNode (Refs.configProblems config))
    result <- report git repo defaultQuery
    nodeRows result >>= assertEqual [nodeA, nodeB] . map statusNode
    forM_ [nodeA, nodeB] $ \node -> do
        row <- nodeRow node result
        expected <- tipOf git repo node
        assertEqual (Available (either error id (parseObjectId format expected))) (statusTip row)
        remote <- remoteOf node result
        assertEqual (Just [remoteRef "origin" node]) (map fst <$> remoteRefs remote)
    a <- nodeRow nodeA result
    case statusWorktrees a of Available trees -> assertEqual 1 (length trees); _ -> fail "Worktree registration lost after upstream failure"
    aRemote <- remoteOf nodeA result
    case remoteUpstream aRemote of
        Available (Just upstream) -> do
            assertEqual (Just "origin") (upstreamRemote upstream)
            assertEqual (Just (localRef nodeA)) (upstreamSource upstream)
        _ -> fail "A's known configuration was discarded with B's bad entry"
    bRemote <- remoteOf nodeB result
    assertEqual Unavailable (remoteUpstream bRemote)
    assertTrue "B has no contextual config diagnostic" (any (\issue -> diagnosticNode issue == Just nodeB && statusCode issue == "upstream_config_invalid") (reportDiagnostics result))
    assertTrue "Original atom failure not retained" (any ((== "upstream_unavailable") . statusCode) (reportDiagnostics result))
    forM_ ["json", "cbor"] $ \encoding -> do
        actual <- callCli executable repo encoding ["status", "-t", "node"]
        assertEqual (ExitFailure 3) (gitExitCode actual)
        assertEqual "" (gitStderr actual)
        wireNodes encoding (gitStdout actual) >>= assertEqual (map (BSC.unpack . nodeIdBytes) [nodeA, nodeB])

symbolicSelection :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
symbolicSelection git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    _ <- ok git repo ["symbolic-ref", BSC.unpack (remoteRef "bad" nodeB), BSC.unpack (localRef nodeB)] ""
    onlyA <- report git repo (selected [nodeA])
    assertEqual [] (reportDiagnostics onlyA)
    onlyB <- report git repo (selected [nodeB])
    assertTrue "Selected symbolic candidate was hidden" (any (\issue -> statusCode issue == "symbolic_remote_ref" && diagnosticNode issue == Just nodeB) (reportDiagnostics onlyB))
    remoteOf nodeB onlyB >>= assertEqual Nothing . remoteRefs
    encodedB <- callCli executable repo "json" ["status", "-t", "node", "-n", BSC.unpack (nodeIdBytes nodeB), "-p", "remote"]
    assertEqual (ExitFailure 3) (gitExitCode encodedB)
    rootObject <- expectRight (Aeson.eitherDecodeStrict' (gitStdout encodedB) :: Either String (Map.Map String Aeson.Value))
    rawRows <- maybe (fail "Missing nodes") fromJson (Map.lookup "nodes" rootObject) :: IO [Map.Map String Aeson.Value]
    case rawRows of
        [row] -> do
            remoteObject <- maybe (fail "Missing remote") fromJson (Map.lookup "remote" row) :: IO (Map.Map String Aeson.Value)
            assertEqual (Just Aeson.Null) (Map.lookup "refs" remoteObject)
        _ -> fail "Expected only B in symbolic candidate response"
    _ <- ok git repo ["symbolic-ref", "--delete", BSC.unpack (remoteRef "bad" nodeB)] ""
    remoteOnly <- expectRight (parseNodeId "33333333-3333-4333-8333-333333333333")
    _ <- ok git repo ["symbolic-ref", BSC.unpack (remoteRef "bad" remoteOnly), BSC.unpack (localRef nodeA)] ""
    defaultResult <- report git repo defaultQuery
    assertEqual [] (reportDiagnostics defaultResult)
    nodeRows defaultResult >>= assertEqual [nodeA, nodeB] . map statusNode
    _ <- ok git repo ["symbolic-ref", BSC.unpack (remoteRef "bad" nodeB), BSC.unpack (localRef nodeB)] ""
    b <- tipOf git repo nodeB
    _ <- ok git repo ["update-ref", BSC.unpack (remoteRef "normal" nodeB), BSC.unpack b] ""
    mixed <- report git repo (selected [nodeB])
    assertTrue "Mixed candidate diagnostic missing" (not (null (reportDiagnostics mixed)))
    remoteOf nodeB mixed >>= assertEqual (Just [remoteRef "normal" nodeB]) . fmap (map fst) . remoteRefs
    let warning = Git $ \invocation -> do
            outcome <- runGit git invocation
            pure $ if "for-each-ref" `elem` gitArguments invocation then fmap (\value -> value{gitStderr = "warning: global omission"}) outcome else outcome
    global <- report warning repo (selected [nodeA])
    assertTrue "Scope filtering hid a global read warning" (any ((== "refs_incomplete") . statusCode) (reportDiagnostics global))
    forM_ [(nodeA, ExitSuccess), (nodeB, ExitFailure 3)] $ \(node, code) -> do
        value <- callCli executable repo "json" ["status", "-t", "node", "-n", BSC.unpack (nodeIdBytes node), "-p", "remote"]
        assertEqual code (gitExitCode value)
    enable git executable repo
    Deploy.deploy executable git repo (parent </> "refused") Nothing >>= expectLeft
    doesDirectoryExist (parent </> "refused") >>= assertEqual False

adapterFailures :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
adapterFailures format git _ repo parent = do
    prepareTracked git repo
    trusted <- snapshot git repo
    let upstream request = any ("%(upstream)" `isInfixOf`) (gitArguments request)
        failed = GitResult (ExitFailure 128) "unreliable stdout" "fixture upstream failure"
        fallback = Git $ \invocation -> if upstream invocation then pure (Right failed) else runGit git invocation
    counts <- newIORef []
    retained <- report (observeGit (\request -> modifyIORef' counts (++ [gitArguments request])) fallback) repo defaultQuery
    nodeRows retained >>= assertEqual [nodeA, nodeB] . map statusNode
    forM_ [nodeA, nodeB] $ \node -> do
        value <- nodeRow node retained
        case statusTip value of Available _ -> pure (); _ -> fail "Fallback discarded a reliable tip"
    args <- readIORef counts
    assertEqual 4 (length [() | call <- args, "for-each-ref" `elem` call])
    assertTrue "Upstream failure was hidden" (any ((== "upstream_unavailable") . statusCode) (reportDiagnostics retained))
    let noRefs = Git $ \invocation -> if "for-each-ref" `elem` gitArguments invocation then pure (Right failed) else runGit git invocation
    unavailable <- report noRefs repo defaultQuery
    nodeRows unavailable >>= assertEqual []
    Validation.loadManagedState noRefs repo >>= expectLeft
    planDeployment noRefs repo trusted (parent </> "refused") >>= expectLeft
    strict <- Refs.readNodeRefs noRefs repo [] format Refs.LocalNodes
    assertEqual [] (Refs.observationRefs strict)
    expectLeft (Refs.requireCompleteRefs strict)
    n <- newIORef (0 :: Int)
    let racing = Git $ \invocation ->
            if upstream invocation
                then pure (Right failed)
                else
                    if "for-each-ref" `elem` gitArguments invocation
                        then do
                            modifyIORef' n (+ 1)
                            count <- readIORef n
                            if count == 2 then pure (Right (GitResult ExitSuccess "" "")) else runGit git invocation
                        else runGit git invocation
    changed <- report racing repo defaultQuery
    assertTrue "Fallback lost ref change detection" (any ((== "observation_changed") . statusCode) (reportDiagnostics changed))

successfulDefault :: FilePath -> FilePath -> IO ()
successfulDefault executable repo = forM_ ["json", "cbor"] $ \encoding -> do
    value <- callCli executable repo encoding ["status", "-t", "node"]
    assertEqual ExitSuccess (gitExitCode value)
    assertEqual "" (gitStderr value)
    wireNodes encoding (gitStdout value) >>= assertEqual (map (BSC.unpack . nodeIdBytes) [nodeA, nodeB])

callCli :: FilePath -> FilePath -> String -> [String] -> IO GitResult
callCli executable repo encoding arguments = do
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
    runGit (nativeGit executable) (GitInvocation repo (["--format", encoding] ++ arguments) "" environment) >>= expectRight

wireNodes :: String -> BS.ByteString -> IO [String]
wireNodes "json" bytes = do
    object <- expectRight (Aeson.eitherDecodeStrict' bytes :: Either String (Map.Map String Aeson.Value))
    value <- maybe (fail "Missing nodes") pure (Map.lookup "nodes" object)
    fields <- fromJson value :: IO [Map.Map String Aeson.Value]
    mapM (\row -> maybe (fail "Missing node") fromJson (Map.lookup "node" row)) fields
wireNodes _ bytes = do
    (rest, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict bytes))
    assertEqual BL.empty rest
    case term of
        CBOR.TMap rootFields | Just (CBOR.TList values) <- lookup (CBOR.TString "nodes") rootFields -> mapM name values
        _ -> fail "Invalid Status CBOR shape"
  where
    name (CBOR.TMap fields) | Just (CBOR.TString value) <- lookup (CBOR.TString "node") fields = fromJson (Aeson.String value)
    name _ = fail "Missing CBOR node"

fromJson :: (Aeson.FromJSON a) => Aeson.Value -> IO a
fromJson value = case Aeson.fromJSON value of Aeson.Success result -> pure result; Aeson.Error message -> fail message
