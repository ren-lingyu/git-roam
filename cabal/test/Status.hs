{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import BatchFixture (runBatchFixture)
import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import CommitProperty (commitTests)
import Control.Monad (forM_, unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isPrefixOf)
import qualified Data.Set as Set
import qualified GitRoam.Application.Inspect as Inspect
import GitRoam.Application.Protection (ProtectionState (..), observeProtection)
import GitRoam.Application.Status
import GitRoam.Application.Worktree (planDeployment)
import GitRoam.Cli
import GitRoam.Git
import qualified GitRoam.Git.Refs as Refs
import GitRoam.Git.Worktrees (Worktree (..))
import GitRoam.ObjectId
import GitRoam.Output
import GitRoam.Protocol.Identity
import StatusRegression (regressionTests)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorkingTreeStatus (workingTreeTests)
import WorktreeFixture

main :: IO ()
main =
    runBatchFixture $
        runTests $
            [ ("Status required type and exact set selection", parser)
            , ("ref observations retain reliable rows but strict views reject incompleteness", partialRefs)
            , ("protection local/effective configuration classification", protection)
            , ("Status JSON/CBOR preserve selected properties and arbitrary bytes", encodings)
            ]
                ++ [("Status lightweight observations and batch upstream " ++ backend ++ " " ++ show format, fixture backend format (nativeQueries format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
                ++ [("Status partial reads and strict callers " ++ backend ++ " " ++ show format, fixture backend format (partialQueries format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
                ++ [("Status CLI reports and argument errors " ++ backend ++ " " ++ show format, fixture backend format cliQueries) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
                ++ regressionTests
                ++ commitTests
                ++ workingTreeTests

first :: [a] -> a
first (value : _) = value
first [] = error "Expected at least one fixture row"

query :: [NodeProperty] -> StatusQuery
query properties = NodeStatusQuery AllNodes (SelectedProperties (Set.fromList properties))

parser :: IO ()
parser = do
    let a = BSC.unpack (nodeIdBytes nodeA)
        b = BSC.unpack (nodeIdBytes nodeB)
        expected = QueryStatus (NodeStatusQuery (SelectedNodes (Set.fromList [nodeA, nodeB])) (SelectedProperties (Set.fromList [TipProperty, RemoteProperty])))
    assertEqual (Right (QueryStatus (query [CommitProperty]))) (parseCommand ["status", "-t", "node", "-p", "commit"])
    assertEqual (Right (QueryStatus (query [StatusProperty]))) (parseCommand ["status", "-t", "node", "-p", "status"])
    assertEqual (Right (QueryStatus RepositoryStatus)) (parseCommand ["status", "--type", "repo"])
    assertEqual (Right (QueryStatus (NodeStatusQuery AllNodes DefaultProperties))) (parseCommand ["status", "-t", "node"])
    assertEqual (Right expected) (parseCommand ["status", "--node", b, "-p", "remote", "-t", "node", "-n", a, "-n", a, "--property", "tip", "-p", "tip"])
    forM_ [["status"], ["status", "--node", a], ["status", "-t", "node", "--type", "node"], ["status", "-t", "repo", "-t", "node"], ["status", "-t", "repo", "-n", a], ["status", "-t", "repo", "-p", "tip"], ["status", "-t", "unknown"], ["status", "-t", "node", "-p", "unknown"], ["status", "-t", "node", "-n", a, b], ["status", "-t", "node", "-n", "bad"], ["status", "-t", "node", "--format", "json"], ["-f", "json", "status", "-t", "node"]] $ expectLeft . parseCommand

partialRefs :: IO ()
partialRefs = forM_ [Sha1, Sha256] $ \format -> do
    let oid = BS.replicate (objectIdLength format) 49
        row node bytes = "refs/heads/" <> nodeIdBytes node <> "\0" <> bytes <> "\0\n"
        good = row nodeA oid
        other = row nodeB oid
        parsed = Refs.decodeNodeRefs format Refs.LocalNodes (good <> row nodeB "bad")
    assertEqual [nodeA] (map Refs.observedNode (Refs.observationRefs parsed))
    assertEqual False (Refs.observationComplete parsed)
    expectLeft (Refs.requireCompleteRefs parsed)
    let duplicate = Refs.decodeNodeRefs format Refs.LocalNodes (good <> row nodeA "bad" <> other)
    assertEqual [nodeB] (map Refs.observedNode (Refs.observationRefs duplicate))
    expectLeft (Refs.requireCompleteRefs duplicate)
    let truncated = Refs.decodeNodeRefs format Refs.LocalNodes (good <> BS.init other)
    assertEqual [nodeA] (map Refs.observedNode (Refs.observationRefs truncated))
    expectLeft (Refs.requireCompleteRefs truncated)
    let fake code stderr = Git (const (pure (Right (GitResult code good stderr))))
    warned <- Refs.readNodeRefs (fake ExitSuccess "warning: omitted ref") "/fixture" [] format Refs.LocalNodes
    assertEqual [nodeA] (map Refs.observedNode (Refs.observationRefs warned))
    expectLeft (Refs.requireCompleteRefs warned)
    failed <- Refs.readNodeRefs (fake (ExitFailure 7) "failed") "/fixture" [] format Refs.LocalNodes
    assertEqual [] (Refs.observationRefs failed)
    expectLeft (Refs.requireCompleteRefs failed)

protection :: IO ()
protection = do
    let expected key = case key of
            "hook.git-roam-reference-transaction.event" -> "reference-transaction\0"
            "hook.git-roam-reference-transaction.command" -> "git-roam --reference-transaction\0"
            _ -> "true\0"
        fake mode = Git $ \invocation -> do
            let args = gitArguments invocation
                bytes = expected (last args)
                result = case mode of
                    0 -> GitResult (ExitFailure 1) "" ""
                    1 -> GitResult ExitSuccess bytes ""
                    2 | "--local" `elem` args -> GitResult (ExitFailure 1) "" ""
                    3 -> GitResult ExitSuccess (bytes <> bytes) ""
                    4 -> GitResult (ExitFailure 128) "" "fixture read failure"
                    5 -> GitResult ExitSuccess bytes "warning: incomplete config"
                    _ -> GitResult ExitSuccess bytes ""
            pure (Right result)
    forM_ [(0, ProtectionDisabled), (1, ProtectionEnabled), (2, ProtectionMisconfigured), (3, ProtectionMisconfigured), (4, ProtectionUnavailable), (5, ProtectionUnavailable)] $ \(mode, state) -> fst <$> observeProtection (fake (mode :: Int)) "/fixture" >>= assertEqual state

encodings :: IO ()
encodings = do
    oid <- expectRight (parseObjectId Sha1 (BS.replicate 40 49))
    let raw = "/raw\n" <> BS.pack [255]
        tree = Worktree raw (Just oid) (Just ("refs/heads/" <> nodeIdBytes nodeA)) True False False (Just "locked\nreason") Nothing
        report = NodesReport [NodeStatus nodeA NotRequested NotRequested (Available [tree]) NotRequested NotRequested] []
        value = statusValue report
    case value of
        Object [("nodes", Array [Object fields]), ("diagnostics", Array [])] -> assertEqual ["node", "worktrees"] (map fst fields)
        _ -> fail "Unexpected selected Status schema"
    parsed <- expectRight (Aeson.eitherDecodeStrict' (encodeValue JsonFormat value) :: Either String Aeson.Value)
    assertTrue "JSON lost bytes" ("base64" `BS.isInfixOf` encodeValue JsonFormat value)
    (rest, term) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict (encodeValue CborFormat value)))
    assertEqual BL.empty rest
    assertTrue "CBOR lost native path bytes" (contains raw term)
    assertEqual (Just parsed) (Aeson.decodeStrict' (encodeValue JsonFormat value))
  where
    contains raw term = case term of
        CBOR.TBytes bytes -> bytes == raw
        CBOR.TMap pairs -> any (contains raw . snd) pairs
        CBOR.TList values -> any (contains raw) values
        _ -> False

runStatus :: Git IO -> FilePath -> StatusQuery -> IO StatusReport
runStatus git repo request = queryStatus git repo request >>= expectRight

rows :: StatusReport -> IO [NodeStatus]
rows (NodesReport values _) = pure values
rows _ = fail "Expected Node report"

nativeQueries :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeQueries format git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    calls <- newIORef []
    let traced = observeGit (\invocation -> modifyIORef' calls (++ [gitArguments invocation])) git
    report <- runStatus traced repo (NodeStatusQuery AllNodes DefaultProperties)
    assertEqual [] (reportDiagnostics report)
    values <- rows report
    assertEqual [nodeA, nodeB] (map statusNode values)
    args <- readIORef calls
    assertEqual 2 (length [() | call <- args, "for-each-ref" `elem` call])
    assertEqual 1 (length [() | call <- args, "--get-regexp" `elem` call])
    assertEqual 1 (length [() | call <- args, "worktree" `elem` call])
    assertEqual [] [call | call <- args, any (`elem` call) ["cat-file", "status", "fetch"]]
    forM_ values $ \value -> do
        assertEqual (Available []) (statusWorktrees value)
        assertEqual (Available (RemoteObservation (Available Nothing) (Just []))) (statusRemote value)
    let branch = BSC.unpack (nodeIdBytes nodeA)
    _ <- ok git repo ["config", "branch." ++ branch ++ ".remote", "."] ""
    _ <- ok git repo ["config", "branch." ++ branch ++ ".merge", "refs/heads/" ++ branch] ""
    local <- runStatus git repo (query [RemoteProperty]) >>= rows
    case statusRemote (first local) of
        Available value -> assertEqual (Available (Just (UpstreamObservation (Just ".") (Just ("refs/heads/" <> nodeIdBytes nodeA)) (Just ("refs/heads/" <> nodeIdBytes nodeA))))) (remoteUpstream value)
        _ -> fail "Missing local upstream"
    _ <- ok git repo ["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"] ""
    _ <- ok git repo ["config", "branch." ++ branch ++ ".remote", "origin"] ""
    _ <- ok git repo ["config", "branch." ++ branch ++ ".merge", "refs/heads/missing"] ""
    missing <- runStatus git repo (query [RemoteProperty]) >>= rows
    case statusRemote (first missing) of
        Available value -> case remoteUpstream value of
            Available (Just upstream) -> assertEqual (Just "refs/heads/missing") (upstreamSource upstream)
            _ -> fail "Lost configured missing upstream"
        _ -> fail "Missing remote report"
    _ <- ok git repo ["config", "--add", "branch." ++ branch ++ ".merge", "refs/heads/other"] ""
    ambiguous <- runStatus git repo (query [RemoteProperty])
    assertTrue "Ambiguous upstream accepted" (any ((== "upstream_ambiguous") . statusCode) (reportDiagnostics ambiguous))
    _ <- ok git repo ["config", "--unset-all", "branch." ++ branch ++ ".merge"] ""
    _ <- ok git repo ["config", "--unset-all", "branch." ++ branch ++ ".remote"] ""
    manual git repo (parent </> "linked worktree\npath") nodeA
    treeReport <- runStatus git repo (query [WorktreesProperty]) >>= rows
    case statusWorktrees (first treeReport) of Available trees -> assertEqual 1 (length trees); _ -> fail "Missing worktree registration"
    -- Non-protocol tip: observation stays available while complete validation fails.
    empty <- BSC.init <$> ok git repo ["mktree"] ""
    invalid <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack empty, "-m", "Not a Node history"] ""
    _ <- ok git repo ["update-ref", "refs/heads/" ++ BSC.unpack (nodeIdBytes nodeB), BSC.unpack invalid] ""
    broken <- runStatus git repo (query [TipProperty])
    assertEqual [] (reportDiagnostics broken)
    bs <- rows broken
    assertEqual (Available (either error id (parseObjectId format invalid))) (statusTip (bs !! 1))
    validation <- Inspect.inspectState git repo [] Nothing
    case validation of Left _ -> pure (); Right value -> assertTrue "Invalid state reported valid" (not (null (Inspect.reportProblems value)))
    -- Increasing the Node set must not add per-Node upstream subprocesses.
    aTip <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeA)] ""
    let candidate prefix node = "refs/remotes/" <> prefix <> "/" <> nodeIdBytes node
    remoteOnly <- expectRight (parseNodeId "33333333-3333-4333-8333-333333333333")
    forM_ [candidate "backup" nodeA, candidate "origin/nested" nodeA, candidate "origin" remoteOnly] $ \name -> do
        _ <- ok git repo ["update-ref", BSC.unpack name, BSC.unpack aTip] ""
        pure ()
    tracked <- runStatus git repo (query [RemoteProperty]) >>= rows
    assertEqual [nodeA, nodeB] (map statusNode tracked)
    case statusRemote (first tracked) of
        Available value -> assertEqual (Just [candidate "backup" nodeA, candidate "origin/nested" nodeA]) (map fst <$> remoteRefs value)
        _ -> fail "Remote candidates were not retained"
    let label n = "aaaaaaaa-aaaa-4aaa-8aaa-" ++ replicate (12 - length (show n)) '0' ++ show n
        updates = BSC.unlines ["create refs/heads/" <> BSC.pack (label n) <> " " <> aTip | n <- [1 :: Int .. 32]]
    _ <- ok git repo ["update-ref", "--stdin"] updates
    largerCalls <- newIORef []
    larger <- runStatus (observeGit (\invocation -> modifyIORef' largerCalls (++ [gitArguments invocation])) git) repo (NodeStatusQuery AllNodes DefaultProperties)
    assertEqual [] (reportDiagnostics larger)
    rows larger >>= assertEqual 34 . length
    largerArgs <- readIORef largerCalls
    assertEqual (length args) (length largerArgs)
    assertEqual 2 (length [() | call <- largerArgs, "for-each-ref" `elem` call])
    assertEqual 1 (length [() | call <- largerArgs, "--get-regexp" `elem` call])

partialQueries :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
partialQueries format git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    trusted <- snapshot git repo
    tip <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeA)] ""
    let good = "refs/heads/" <> nodeIdBytes nodeA <> "\0" <> tip <> "\0\n"
        faulty = Git $ \invocation ->
            if "for-each-ref" `elem` gitArguments invocation
                then pure (Right (GitResult ExitSuccess (good <> "refs/heads/" <> nodeIdBytes nodeB <> "\0invalid\0\n") "warning: partial fixture"))
                else runGit git invocation
    report <- runStatus faulty repo (query [TipProperty])
    values <- rows report
    assertEqual [nodeA] (map statusNode values)
    assertEqual (Available (either error id (parseObjectId format tip))) (statusTip (first values))
    assertTrue "Partial query lost diagnostics" (not (null (reportDiagnostics report)))
    Inspect.inspectState faulty repo [] Nothing >>= expectLeft
    planDeployment faulty repo trusted (parent </> "refused") >>= expectLeft
    let noTrees = Git $ \invocation ->
            if "worktree" `elem` gitArguments invocation
                then pure (Left (GitTransportError "fixture worktree read"))
                else runGit git invocation
    failedTrees <- runStatus noTrees repo (query [TipProperty, WorktreesProperty]) >>= rows
    assertEqual (Available (either error id (parseObjectId format tip))) (statusTip (first failedTrees))
    assertEqual Unavailable (statusWorktrees (first failedTrees))
    let noConfig = Git $ \invocation ->
            if "--get-regexp" `elem` gitArguments invocation
                then pure (Left (GitTransportError "fixture config read"))
                else runGit git invocation
    unknown <- runStatus noConfig repo (query [RemoteProperty])
    assertTrue "Config failure has no diagnostic" (any ((== "upstream_unavailable") . statusCode) (reportDiagnostics unknown))
    unknownRows <- rows unknown
    case statusRemote (first unknownRows) of
        Available remote -> do
            assertEqual Unavailable (remoteUpstream remote)
            assertEqual (Just []) (remoteRefs remote)
        _ -> fail "Reliable remote refs lost after config failure"
    let object = statusValue (NodesReport failedTrees [])
    _ <- expectRight (Aeson.eitherDecodeStrict' (encodeValue JsonFormat object) :: Either String Aeson.Value)
    counts <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    modifyIORef' counts (+ 1)
                    n <- readIORef counts
                    if n == 2 then pure (Right (GitResult ExitSuccess "" "")) else runGit git invocation
                else runGit git invocation
    changed <- runStatus racing repo (query [TipProperty])
    assertTrue "Ref changes not diagnosed" (any ((== "observation_changed") . statusCode) (reportDiagnostics changed))

cliQueries :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliQueries git executable repo parent = do
    root git repo nodeA
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
        call encoding location args = runGit (nativeGit executable) (GitInvocation location (["--format", encoding] ++ args) "" environment) >>= expectRight
        decode encoding bytes =
            if encoding == "json"
                then do
                    _ <- expectRight (Aeson.eitherDecodeStrict' bytes :: Either String Aeson.Value)
                    assertEqual 10 (BS.last bytes)
                else do
                    (rest, _) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict bytes))
                    assertEqual BL.empty rest
    forM_ ["json", "cbor"] $ \encoding -> do
        result <- call encoding repo ["status", "-t", "node", "-p", "tip", "-n", BSC.unpack (nodeIdBytes nodeA), "-n", BSC.unpack (nodeIdBytes nodeB)]
        assertEqual (ExitFailure 3) (gitExitCode result)
        decode encoding (gitStdout result)
        assertEqual "" (gitStderr result)
        repoStatus <- call encoding repo ["status", "-t", "repo"]
        assertEqual ExitSuccess (gitExitCode repoStatus)
        decode encoding (gitStdout repoStatus)
        missing <- call encoding parent ["status", "-t", "node"]
        assertEqual "" (gitStdout missing)
        assertEqual (ExitFailure 3) (gitExitCode missing)
        _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr missing) :: Either String Aeson.Value)
        invalid <- call encoding repo ["status"]
        assertEqual (ExitFailure 2) (gitExitCode invalid)
        assertEqual "" (gitStdout invalid)
        _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr invalid) :: Either String Aeson.Value)
        pure ()
    calls <- newIORef []
    let observed = observeGit (\request -> modifyIORef' calls (++ [gitArguments request])) git
    _ <- runStatus observed repo RepositoryStatus
    args <- readIORef calls
    unless (null [callArgs | callArgs <- args, any (`elem` callArgs) ["for-each-ref", "worktree", "cat-file", "status"]]) (fail "Repo query performed unrelated Node work")
    tipCalls <- newIORef []
    _ <- runStatus (observeGit (\request -> modifyIORef' tipCalls (++ [gitArguments request])) git) repo (query [TipProperty])
    observedTips <- readIORef tipCalls
    assertEqual [] [callArgs | callArgs <- observedTips, any (`elem` callArgs) ["cat-file", "status", "worktree", "config"]]
