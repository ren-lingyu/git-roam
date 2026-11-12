{-# LANGUAGE OverloadedStrings #-}

module IntegrationAcceptance (acceptanceTests) where

import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Set as Set
import qualified GitRoam.Application.Check as Check
import GitRoam.Application.Protection (ownHookBypass)
import qualified GitRoam.Application.Status as Status
import GitRoam.Application.Validation (loadManagedState)
import GitRoam.Git
import GitRoam.Git.Objects (checkStoredConnectivity)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import System.Directory (doesDirectoryExist, doesPathExist, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WireAssertions
import WorktreeFixture

acceptanceTests :: [(String, IO ())]
acceptanceTests =
    [("missing-object accumulation preserves order and type precedence", missingOrder)]
        ++ [ (backend ++ "/" ++ show format ++ ": " ++ name, fixture backend format action)
           | backend <- ["files", "reftable"]
           , format <- [Sha1, Sha256]
           , (name, action) <- [("executable cross-command contracts and read-only observations", crossCommand), ("partial refs, config indexing and constant query counts", costs), ("promisor missing blobs never trigger lazy fetch", noLazyFetch), ("native default Status uses constant subprocess launches", nativeCosts)]
           ]

crossCommand :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
crossCommand git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
        call encoding location arguments = runGit (nativeGit executable) (GitInvocation location (["--format", encoding] ++ arguments) "" environment) >>= expectRight
        success encoding arguments = do
            result <- call encoding repo arguments
            assertEqual ExitSuccess (gitExitCode result)
            assertEqual "" (gitStderr result)
            decodeWire encoding (gitStdout result)
        branch = BSC.unpack (nodeIdBytes nodeA)
        path = parent </> "node-a"
    forM_ ["json", "cbor"] $ \encoding -> do
        success encoding ["status", "-t", "repo"] >>= field "repository" >>= field "protection" >>= field "state" >>= assertEqual (Aeson.String "disabled")
        success encoding ["check"] >>= field "valid" >>= assertEqual (Aeson.Bool True)
    manual git repo path nodeA
    enable git executable repo
    writeFile (path </> "untracked-data") "preserve me\n"
    beforeRefs <- ok git repo ["show-ref"] ""
    beforeConfig <- BS.readFile (repo </> ".git" </> "config")
    indexPath <- BSC.unpack . BSC.init <$> ok git path ["rev-parse", "--path-format=absolute", "--git-path", "index"] ""
    beforeIndex <- BS.readFile indexPath
    forM_ ["json", "cbor"] $ \encoding -> do
        status <- success encoding ["status", "-t", "node", "-n", branch, "-p", "status"]
        row <- field "nodes" status >>= asList >>= exactlyOne
        summary <- field "status" row >>= asList >>= exactlyOne
        field "state" summary >>= assertEqual (Aeson.String "dirty")
        success encoding ["check", "--show-refs"] >>= field "valid" >>= assertEqual (Aeson.Bool True)
        result <- call encoding repo ["undeploy"]
        assertTrue "Unsafe removal succeeded" (gitExitCode result /= ExitSuccess)
        if BS.null (gitStdout result)
            then do
                _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr result) :: Either String Aeson.Value)
                pure ()
            else do
                _ <- decodeWire encoding (gitStdout result)
                assertEqual "" (gitStderr result)
        doesDirectoryExist path >>= assertEqual True
        readFile (path </> "untracked-data") >>= assertEqual "preserve me\n"
    ok git repo ["show-ref"] "" >>= assertEqual beforeRefs
    BS.readFile (repo </> ".git" </> "config") >>= assertEqual beforeConfig
    BS.readFile indexPath >>= assertEqual beforeIndex
    -- Actual executable parser and help, including unused wrapper paths.
    let invalid = [["status"], ["status", "-t", "node", "-t", "node"], ["status", "-t", "repo", "-p", "tip"], ["status", "-t", "node", "-p", "unknown"], ["status", "-t", "node", "-n", "bad"], ["status", "-t", "node", "-p"], ["check", "--node", branch], ["check", "--show-refs", "--show-refs"], ["status", "-t", "node", "--format", "json"]]
    forM_ invalid $ \arguments -> do
        result <- call "json" repo arguments
        assertEqual (ExitFailure 2) (gitExitCode result)
        assertEqual "" (gitStdout result)
        _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr result) :: Either String Aeson.Value)
        pure ()
    forM_ [["--help"], ["status", "--help"], ["check", "--help"], ["node", "--help"]] $ \arguments -> do
        result <- call "json" repo arguments
        assertEqual ExitSuccess (gitExitCode result)
        assertTrue "Help disappeared" (not (BS.null (gitStdout result)))
    let unused = parent </> "unused"
    duplicate <- success "json" ["--deploy-path", unused, "status", "-t", "node", "-n", branch, "-n", branch, "-p", "tip", "-p", "tip"] >>= field "nodes" >>= asList >>= exactlyOne
    a <- BSC.init <$> ok git repo ["rev-parse", branch] ""
    assertEqual (Aeson.object ["node" Aeson..= readText (nodeIdBytes nodeA), "tip" Aeson..= readText a]) duplicate
    doesPathExist unused >>= assertEqual False
    -- Corrupt branch identity through an explicit fixture-only Hook bypass.
    b <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB)] ""
    _ <- ok git repo (ownHookBypass ++ ["update-ref", "refs/heads/" ++ branch, BSC.unpack b]) ""
    forM_ ["json", "cbor"] $ \encoding -> do
        success encoding ["status", "-t", "node", "-n", branch, "-p", "tip"] >>= field "nodes" >>= asList >>= exactlyOne >>= field "tip" >>= assertEqual (Aeson.String (readText b))
        invalidReport <- call encoding repo ["check"]
        assertEqual (ExitFailure 1) (gitExitCode invalidReport)
        assertEqual "" (gitStderr invalidReport)
        decoded <- decodeWire encoding (gitStdout invalidReport)
        problem <- diagnosticAt 0 decoded
        field "code" problem >>= assertEqual (Aeson.String "identity_mismatch")
        context <- field "context" problem
        field "node" context >>= assertEqual (Aeson.String (readText (nodeIdBytes nodeA)))
        field "object" context >>= assertEqual (Aeson.String (readText b))
    loadManagedState git repo >>= expectLeft
    textCheck <- call "text" repo ["check"]
    assertEqual (ExitFailure 1) (gitExitCode textCheck)
    assertTrue "Check text report omitted conclusion" ("invalid\n" `BS.isPrefixOf` gitStdout textCheck)
    assertEqual "" (gitStderr textCheck)
    let missingNode = "33333333-3333-4333-8333-333333333333"
    textStatus <- call "text" repo ["status", "-t", "node", "-n", missingNode, "-p", "tip"]
    assertEqual (ExitFailure 3) (gitExitCode textStatus)
    assertTrue "Status text diagnostic did not use stderr" (not (BS.null (gitStderr textStatus)))
    forM_ ["json", "cbor"] $ \encoding -> do
        result <- call encoding repo ["status", "-t", "node", "-n", missingNode, "-p", "tip"]
        assertEqual (ExitFailure 3) (gitExitCode result)
        assertEqual "" (gitStderr result)
        decoded <- decodeWire encoding (gitStdout result)
        diagnosticAt 0 decoded >>= field "code" >>= assertEqual (Aeson.String "node_not_found")
  where
    readText = either error id . Aeson.eitherDecodeStrict' . (\bytes -> "\"" <> bytes <> "\"")

exactlyOne :: [a] -> IO a
exactlyOne [value] = pure value
exactlyOne _ = fail "Expected exactly one record"

asList :: Aeson.Value -> IO [Aeson.Value]
asList value = case Aeson.fromJSON value of Aeson.Success values -> pure values; Aeson.Error message -> fail message

costs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
costs git _ repo _ = do
    root git repo nodeA
    oid <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeA)] ""
    let uuid i = BSC.pack (replicate (8 - length (show i)) '0' ++ show i ++ "-0000-4000-8000-000000000000")
        request = Status.NodeStatusQuery Status.AllNodes Status.DefaultProperties
        run size fault = do
            calls <- newIORef []
            let observed = Git $ \invocation -> do
                    modifyIORef' calls (gitArguments invocation :)
                    assertEqual (Just (Just "1")) (lookup "GIT_NO_LAZY_FETCH" (gitEnvironment invocation))
                    assertEqual (Just (Just "0")) (lookup "GIT_OPTIONAL_LOCKS" (gitEnvironment invocation))
                    let arguments = gitArguments invocation
                    if "for-each-ref" `elem` arguments
                        then do
                            let upstream = any ("%(upstream)" `isInfixOf`) arguments
                                rows = ["refs/heads/" <> uuid i <> "\0" <> oid <> "\0" <> (if upstream then "\0\0" else "") <> "\n" | i <- [1 .. size]]
                            pure (Right (GitResult ExitSuccess (BS.concat rows) (if fault then "warning: partial" else "")))
                        else
                            if "--get-regexp" `elem` arguments
                                then pure (Right (GitResult ExitSuccess (BS.concat [BS.concat (replicate (if i == 1 then 2 else 1) ("branch." <> uuid i <> ".remote\0")) | i <- [1 .. size - 1]]) ""))
                                else do
                                    assertTrue "Query executed a write/network/history command" (not (any (`elem` arguments) ["fetch", "push", "update-ref", "status", "cat-file"]))
                                    runGit git invocation
            report <- Status.queryStatus observed repo request >>= expectRight
            rows <- case report of Status.NodesReport rows _ -> pure rows; _ -> fail "Node report expected"
            assertEqual size (length rows)
            forM_ (init rows) $ \row -> case Status.statusRemote row of Status.Available remote -> assertEqual Status.Unavailable (Status.remoteUpstream remote); _ -> fail "Remote property missing"
            case Status.statusRemote (last rows) of Status.Available remote -> assertEqual (Status.Available Nothing) (Status.remoteUpstream remote); _ -> fail "Unaffected Node lost"
            assertEqual (size - 1) (length [problem | problem <- Status.reportDiagnostics report, Status.statusCode problem == "upstream_config_invalid"])
            if fault
                then do
                    checked <- Check.checkManagedState observed repo >>= expectRight
                    assertEqual Check.Inconclusive (Check.checkConclusion checked)
                    loadManagedState observed repo >>= expectLeft
                    pure ()
                else pure ()
            length <$> readIORef calls
    small <- run (10 :: Int) False
    large <- run 1000 False
    assertEqual small large
    _ <- run 10 True
    -- A global config command failure still taints every selected Node.
    let failed = Git $ \invocation -> if "--get-regexp" `elem` gitArguments invocation then pure (Left (GitTransportError "global config failure")) else runGit git invocation
    report <- Status.queryStatus failed repo (Status.NodeStatusQuery (Status.SelectedNodes (Set.singleton nodeA)) Status.DefaultProperties) >>= expectRight
    case report of
        Status.NodesReport [row] _ -> case Status.statusRemote row of
            Status.Available remote -> assertEqual Status.Unavailable (Status.remoteUpstream remote)
            _ -> fail "Remote missing"
        _ -> fail "Row missing"

missingOrder :: IO ()
missingOrder = do
    let oid byte = either error id (parseObjectId Sha1 (BS.replicate 40 byte))
        commit = oid 97
        tree = oid 98
        blobs = map oid [99, 100, 101]
        source = HistorySource (const (pure (Right (CommitObject tree [])))) (const (pure (Right [TreeEntry (BSC.pack (show index)) RegularFile object | (index, object) <- zip [1 :: Int ..] blobs])))
        adapter wrong = Git $ \invocation -> pure $ Right $ GitResult ExitSuccess (BS.concat [objectIdBytes object <> (if wrong && object == blobs !! 1 then " tree\n" else " missing\n") | object <- blobs, objectIdBytes object `elem` BSC.lines (gitInput invocation)]) ""
    checkStoredConnectivity (adapter False) "." [] source [commit] >>= assertEqual (Right blobs)
    checkStoredConnectivity (adapter True) "." [] source [commit] >>= assertEqual (Left (blobs !! 1, WrongObjectType "tree"))

-- Native trace records detect subprocesses launched inside Git itself, which an
-- application-level adapter observer alone cannot see. The remote is local-only.
noLazyFetch :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
noLazyFetch git _ repo parent = do
    root git repo nodeA
    let branch = BSC.unpack (nodeIdBytes nodeA)
    marker <- BSC.unpack . BSC.init <$> ok git repo ["rev-parse", branch ++ ":" ++ branch ++ "/.roam"] ""
    removeFile (repo </> ".git" </> "objects" </> take 2 marker </> drop 2 marker)
    forM_ [("core.repositoryformatversion", "1"), ("extensions.partialClone", "origin"), ("remote.origin.promisor", "true"), ("remote.origin.url", parent </> "unavailable-remote.git")] $ \(key, value) -> do
        _ <- ok git repo ["config", key, value] ""
        pure ()
    let trace = parent </> "query-trace.jsonl"
        observed = withGitEnvironment [("GIT_TRACE2_EVENT", Just trace), ("GIT_ALLOW_PROTOCOL", Just "file")] git
    report <- Check.checkManagedState observed repo >>= expectRight
    assertEqual Check.Invalid (Check.checkConclusion report)
    assertEqual ["objects_missing"] (map Check.checkCode (Check.checkDiagnostics report))
    loadManagedState observed repo >>= expectLeft
    status <- Status.queryStatus observed repo (Status.NodeStatusQuery Status.AllNodes (Status.SelectedProperties (Set.singleton Status.TipProperty))) >>= expectRight
    assertEqual [] (Status.reportDiagnostics status)
    records <- BSC.lines <$> BS.readFile trace
    assertTrue "Native Git trace is empty" (not (null records))
    forM_ records $ \record -> do
        value <- expectRight (Aeson.eitherDecodeStrict' record)
        event <- field "event" value
        if event `elem` map Aeson.String ["start", "child_start"]
            then do
                arguments <- field "argv" value >>= asList
                assertTrue "Read-only observation triggered lazy fetch" (Aeson.String "fetch" `notElem` arguments)
            else pure ()

-- Default queries have no raw scoped requests: each observeGit event here is
-- one native Git launch, rather than one request within a batch child.
nativeCosts :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeCosts git _ repo _ = do
    let add index = do
            let digits = show index
            node <- expectRight (parseNodeId (BSC.pack (replicate (8 - length digits) '0' ++ digits ++ "-0000-4000-8000-000000000000")))
            root git repo node
        count expected = do
            calls <- newIORef []
            let measured = observeGit (\invocation -> modifyIORef' calls (gitArguments invocation :)) git
            report <- Status.queryStatus measured repo (Status.NodeStatusQuery Status.AllNodes Status.DefaultProperties) >>= expectRight
            assertEqual [] (Status.reportDiagnostics report)
            case report of Status.NodesReport rows _ -> assertEqual expected (length rows); _ -> fail "Node report expected"
            arguments <- readIORef calls
            assertTrue "Default query read objects or worktree files" (all (\args -> not (any (`elem` args) ["cat-file", "status", "fetch", "push"])) arguments)
            assertEqual 2 (length [args | args <- arguments, "for-each-ref" `elem` args])
            assertEqual 1 (length [args | args <- arguments, "worktree" `elem` args])
            pure (length arguments)
    forM_ [1 :: Int .. 10] add
    small <- count 10
    forM_ [11 :: Int .. 100] add
    large <- count 100
    assertEqual small large
