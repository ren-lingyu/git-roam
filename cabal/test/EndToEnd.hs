{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import Control.Exception (bracket_)
import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History (contextParents, reachableHistory)
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Worktree.Paths (decodePath, shortName)
import IntegrationAcceptance (acceptanceTests)
import System.Directory (createDirectory, doesDirectoryExist, doesPathExist, findExecutable, getPermissions, makeAbsolute, setOwnerExecutable, setPermissions)
import System.Environment (getEnvironment, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath (searchPathSeparator, (</>))
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        acceptanceTests
            ++ [("structured command lifecycle " ++ backend ++ " " ++ show format, fixture backend format structuredLifecycle) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [("public CLI lifecycle and native synchronization " ++ backend ++ " " ++ show format, fixture backend format (lifecycle backend format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [("global deployment wrapper and independent Hook " ++ backend ++ " " ++ show format, fixture backend format (globalDeploymentPath format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [("native ref maintenance preserves Node deletion protection " ++ backend ++ " " ++ show format, fixture backend format (refMaintenance backend)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

refMaintenance :: String -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
refMaintenance backend git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    let linked = parent </> "linked"
        branch node = "refs/heads/" ++ BSC.unpack (nodeIdBytes node)
        loose node = repo </> ".git" </> "refs" </> "heads" </> BSC.unpack (nodeIdBytes node)
        run location arguments input = runGit git (GitInvocation location arguments input []) >>= expectRight
        maintain arguments = do
            result <- run linked arguments ""
            assertEqual ExitSuccess (gitExitCode result)
            assertEqual BS.empty (gitStderr result)
        refuse arguments input = do
            before <- snapshot git repo
            result <- run repo arguments input
            assertTrue "Native Node deletion succeeded" (gitExitCode result /= ExitSuccess)
            assertTrue "Deletion was not refused by Git-roam" ("Node deletion requires an explicit Git-roam operation" `BS.isInfixOf` gitStderr result)
            snapshot git repo >>= assertEqual before
        refuseDeletions = do
            old <- BSC.init <$> ok git repo ["rev-parse", branch nodeB] ""
            aOld <- BSC.init <$> ok git repo ["rev-parse", branch nodeA] ""
            forM_ [["update-ref", "-d", branch nodeB], ["update-ref", "-d", branch nodeB, BSC.unpack old], ["branch", "-D", BSC.unpack (nodeIdBytes nodeB)]] $ \arguments -> refuse arguments ""
            refuse ["update-ref", "--stdin"] (BSC.unlines ["start", "delete " <> BSC.pack (branch nodeB) <> " " <> old, "prepare", "commit"])
            refuse ["update-ref", "--stdin"] (BSC.unlines ["start", "delete " <> BSC.pack (branch nodeB) <> " " <> old, "update " <> BSC.pack (branch nodeA) <> " " <> aOld, "prepare", "commit"])
        reflog = ok git linked ["reflog", "show", "--format=%H%x00%gs", branch nodeB] ""
    manual git repo linked nodeA
    enable git executable repo
    initial <- snapshot git repo
    config <- ok git repo ["config", "--local", "--get-regexp", "^hook\\."] ""
    beforeLog <- reflog
    -- Exercise real deletion first with loose-only, then duplicate, then packed-only refs.
    refuseDeletions
    maintain ["pack-refs", "--all", "--no-prune"]
    if backend == "files"
        then forM_ [nodeA, nodeB] $ \node -> doesPathExist (loose node) >>= assertEqual True
        else pure ()
    refuseDeletions
    maintain ["pack-refs", "--all", "--prune"]
    maintain ["pack-refs", "--all", "--prune"]
    if backend == "files"
        then forM_ [nodeA, nodeB] $ \node -> doesPathExist (loose node) >>= assertEqual False
        else pure ()
    snapshot git repo >>= assertEqual initial
    reflog >>= assertEqual beforeLog
    refuseDeletions
    _ <- ok git linked ["commit", "--allow-empty", "-m", "Content after ref packing"] ""
    advanced <- snapshot git repo
    maintain ["maintenance", "run", "--task=pack-refs"]
    snapshot git repo >>= assertEqual advanced
    if backend == "files"
        then doesPathExist (loose nodeA) >>= assertEqual False
        else pure ()
    ok git repo ["config", "--local", "--get-regexp", "^hook\\."] "" >>= assertEqual config

lifecycle :: String -> ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lifecycle backend format git executable repo parent = do
    inherited <- getEnvironment
    let environment =
            [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
                ++ [ ("GIT_CONFIG_NOSYSTEM", Just "1")
                   , ("GIT_CONFIG_GLOBAL", Just "/dev/null")
                   , ("GIT_AUTHOR_NAME", Just "Tutorial")
                   , ("GIT_AUTHOR_EMAIL", Just "tutorial@example.invalid")
                   , ("GIT_COMMITTER_NAME", Just "Tutorial")
                   , ("GIT_COMMITTER_EMAIL", Just "tutorial@example.invalid")
                   ]
        call location args = runGit (nativeGit executable) (GitInvocation location args "" environment) >>= expectRight
        roam location args = do
            result <- call location args
            assertEqual ExitSuccess (gitExitCode result)
            pure (gitStdout result)
        field prefix bytes = case [value | line <- BSC.lines bytes, Just value <- [BS.stripPrefix (prefix <> " ") line]] of
            [value] -> pure value
            _ -> fail ("Missing output field: " ++ BSC.unpack prefix ++ " in " ++ show bytes)
        nodeFrom output = field "node" output >>= expectRight . parseNodeId
        checkpointFrom output = field "checkpoint" output >>= expectRight . parseObjectId format
        uuid = BSC.unpack . nodeIdBytes
        oid = BSC.unpack . objectIdBytes
        branch node = "refs/heads/" ++ uuid node
        pushNodes nodes = ok git repo (["push", relay] ++ [branch node ++ ":" ++ branch node | node <- nodes]) "" >> pure ()
        tip location node = BSC.init <$> ok git location ["rev-parse", branch node] "" >>= expectRight . parseObjectId format
        nodePath location node = do
            records <- listWorktrees git location format >>= expectRight
            case [treePath record | record <- records, worktreeNode record == Just node] of
                [path] -> decodePath path
                _ -> fail "Expected exactly one deployed worktree"
        edit location node text = do
            path <- nodePath location node
            writeFile (path </> uuid node </> "note.org") text
            _ <- ok git path ["add", "--", uuid node ++ "/note.org"] ""
            _ <- ok git path ["commit", "-m", "Write a note"] ""
            pure path
        checkpoint location message context =
            roam location (["checkpoint", "-m", message] ++ concatMap (\revision -> ["--context", revision]) context) >>= checkpointFrom
        confirmDelete location node = do
            plan <- roam location ["node", "delete", "--node", uuid node, "--dry-run"] >>= field "plan"
            _ <- roam location ["node", "delete", "--node", uuid node, "--confirm", BSC.unpack plan]
            pure ()
        check location = roam location ["check"] >> pure ()
        deploymentRoot = parent </> "nodes"
        clone = parent </> "clone"
        relay = parent </> "remote.git"
        cloneRoot = parent </> "clone-nodes"
    -- Ordinary main is the clone entry point, separate from every Node identity.
    _ <- ok git repo ["commit", "--allow-empty", "-m", "Repository entry point"] ""
    _ <- roam repo ["enable"]
    a <- roam repo ["node", "create", "--path", deploymentRoot] >>= nodeFrom
    b <- roam repo ["node", "create", "--path", deploymentRoot] >>= nodeFrom
    assertTrue "UUID collision" (a /= b)
    aRoot <- tip repo a
    bPath <- edit repo b "* B version zero\n"
    b0 <- checkpoint bPath "Confirm B0" [oid aRoot]
    aPath <- edit repo a "* A uses B0\n"
    a0 <- checkpoint aPath "Confirm A0" [oid b0]
    _ <- edit repo b "* B version one\n"
    b1 <- checkpoint bPath "Confirm B1" [oid aRoot]
    source <- snapshot git repo
    contextsA0 <- expectRight (contextParents (managedHistory source) a0)
    assertEqual [b0] contextsA0
    check repo
    _ <- roam aPath ["status", "-t", "node"]

    -- Clone transports the Git DAG; deployment needs no dependency-closure
    -- expansion because every context is already represented by Git parents.
    _ <- ok git parent ["init", "--bare", "--initial-branch=main", "--ref-format=" ++ backend, "--object-format=" ++ if format == Sha1 then "sha1" else "sha256", relay] ""
    _ <- ok git repo ["push", relay, "refs/heads/main:refs/heads/main"] ""
    pushNodes [a, b]
    _ <- ok git parent ["clone", "--no-local", "--ref-format=" ++ backend, relay, clone] ""
    beforeDeploy <- snapshot git clone
    assertEqual Map.empty (managedRefs beforeDeploy)
    _ <- roam clone ["enable"]
    _ <- roam clone ["deploy", "--path", cloneRoot]
    copied <- snapshot git clone
    assertEqual (managedRefs source) (managedRefs copied)
    forM_ [a, b] $ \node -> do
        upstream <- ok git clone ["config", "--get", "branch." ++ uuid node ++ ".merge"] ""
        assertEqual (BSC.pack (branch node) <> "\n") upstream
    check clone

    -- Fetch/deploy does not advance an existing local Node branch. Native
    -- fast-forward remains available and the installed Hook validates it.
    _ <- edit repo b "* B version two\n"
    b2 <- checkpoint bPath "Confirm B2" [oid aRoot]
    pushNodes [b]
    _ <- ok git clone ["fetch", "origin"] ""
    _ <- roam clone ["deploy", "--path", cloneRoot]
    tip clone b >>= assertEqual b1
    clonedB <- nodePath clone b
    writeFile (clonedB </> uuid b </> "note.org") "unsaved local edits\n"
    rejected <- runGit git (GitInvocation clonedB ["merge", "--ff-only", "refs/remotes/origin/" ++ uuid b] "" []) >>= expectRight
    assertTrue "Unsafe native update overwrote local content" (gitExitCode rejected /= ExitSuccess)
    readFile (clonedB </> uuid b </> "note.org") >>= assertEqual "unsaved local edits\n"
    tip clone b >>= assertEqual b1
    -- Explicitly restore only this fixture-owned file before safe native FF.
    writeFile (clonedB </> uuid b </> "note.org") "* B version one\n"
    _ <- ok git clonedB ["merge", "--ff-only", "refs/remotes/origin/" ++ uuid b] ""
    tip clone b >>= assertEqual b2
    readFile (clonedB </> uuid b </> "note.org") >>= assertEqual "* B version two\n"
    check clone

    -- A and B advance together. The transaction is validated against the
    -- complete old/new managed states, including the selected context ancestry.
    _ <- edit repo b "* B version three\n"
    b3 <- checkpoint bPath "Confirm B3" [oid aRoot]
    a1 <- checkpoint aPath "A now uses B3" [oid b3]
    pushNodes [a, b]
    _ <- roam clone ["undeploy"]
    _ <- ok git clone ["fetch", "origin"] ""
    let updates = BSC.unlines ["start", "update " <> BSC.pack (branch a) <> " " <> objectIdBytes a1 <> " " <> objectIdBytes a0, "update " <> BSC.pack (branch b) <> " " <> objectIdBytes b3 <> " " <> objectIdBytes b2, "prepare", "commit"]
    _ <- ok git clone ["update-ref", "--stdin"] updates
    tip clone a >>= assertEqual a1
    tip clone b >>= assertEqual b3
    check clone
    _ <- roam clone ["deploy", "--path", cloneRoot]
    check clone

    -- Deleting B is non-cascading even while A's current Checkpoint records B3.
    original <- snapshot git repo
    assertEqual (Just b3) (Map.lookup b (managedRefs original))
    assertEqual (Just a1) (Map.lookup a (managedRefs original))
    _ <- roam clone ["undeploy"]
    confirmDelete clone b
    afterB <- snapshot git clone
    assertEqual (Map.singleton a a1) (managedRefs afterB)
    retainedByA <- expectRight (reachableHistory (managedHistory afterB) a1)
    assertTrue "Deleting B removed its referenced history" (Set.member b3 retainedByA)
    check clone
    confirmDelete clone a
    empty <- snapshot git clone
    assertEqual Map.empty (managedRefs empty)
    check clone
    _ <- roam clone ["undeploy"]
    _ <- roam clone ["disable"]
    check clone
    -- Source worktrees and identities are independent of the clone's removal.
    doesDirectoryExist aPath >>= assertEqual True
    doesDirectoryExist bPath >>= assertEqual True
    _ <- roam repo ["undeploy"]
    check repo
    _ <- roam repo ["disable"]
    finalSource <- snapshot git repo
    assertEqual (managedRefs original) (managedRefs finalSource)

-- A real PATH wrapper prefixes *every* invocation, including Git's configured
-- Hook command. Its deployment root must not become a Hook precondition.
globalDeploymentPath :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
globalDeploymentPath format git executable repo parent = do
    shell <- findExecutable "sh" >>= maybe (fail "A shell is needed for the wrapper fixture") makeAbsolute
    previousPath <- lookupEnv "PATH"
    inherited <- getEnvironment
    let environment =
            [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
                ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null"), ("GIT_AUTHOR_NAME", Just "Wrapper"), ("GIT_AUTHOR_EMAIL", Just "wrapper@example.invalid"), ("GIT_COMMITTER_NAME", Just "Wrapper"), ("GIT_COMMITTER_EMAIL", Just "wrapper@example.invalid")]
        rootPath = parent </> "nodes with spaces"
        bin = parent </> "wrapper-bin"
        wrapper = bin </> "git-roam"
        quote value = "'" ++ concatMap (\c -> if c == '\'' then "'\\''" else [c]) value ++ "'"
        call program location args input = runGit (nativeGit program) (GitInvocation location args input environment) >>= expectRight
        wrapped args = do
            result <- call wrapper repo args ""
            assertEqual ExitSuccess (gitExitCode result)
            pure (gitStdout result)
        canonical node = BSC.unpack (nodeIdBytes node)
        unusedFile = parent </> "unused-deployment-file"
    createDirectory bin
    writeFile wrapper ("#!" ++ shell ++ "\nexec " ++ quote executable ++ " --format text --deploy-path " ++ quote rootPath ++ " \"$@\"\n")
    permissions <- getPermissions wrapper
    setPermissions wrapper (setOwnerExecutable True permissions)
    bracket_ (setEnv "PATH" (bin ++ [searchPathSeparator] ++ maybe "" id previousPath)) (maybe (unsetEnv "PATH") (setEnv "PATH") previousPath) $ do
        _ <- wrapped ["enable"]
        _ <- wrapped ["node", "create", "--id", canonical nodeA]
        _ <- wrapped ["node", "create", "--id", canonical nodeB]
        let aPath = rootPath </> shortName nodeA
        doesDirectoryExist aPath >>= assertEqual True
        ok git repo ["config", "--get", "hook.git-roam-reference-transaction.command"] "" >>= assertEqual "git-roam --reference-transaction\n"
        writeFile (aPath </> canonical nodeA </> "note.org") "Wrapper content\n"
        _ <- ok git aPath ["add", "--", canonical nodeA ++ "/note.org"] ""
        _ <- ok git aPath ["commit", "-m", "Native Content through wrapped Hook"] ""
        before <- snapshot git repo
        let refs = managedRefs before
            a = refs Map.! nodeA
            b = refs Map.! nodeB
            row new = objectIdBytes a <> " " <> objectIdBytes new <> " refs/heads/" <> nodeIdBytes nodeA <> "\n"
        -- Even invalid public deployment-path values are irrelevant to the
        -- internal Hook; its original transaction validation must still run.
        accepted <- call executable repo ["--deploy-path", "relative", "--reference-transaction", "prepared"] (row a)
        assertEqual ExitSuccess (gitExitCode accepted)
        refused <- call executable repo ["--deploy-path", "relative", "--reference-transaction", "prepared"] (row b)
        assertEqual (ExitFailure 1) (gitExitCode refused)
        assertTrue "Deployment parsing replaced Hook validation" ("reference update refused:" `BS.isInfixOf` gitStderr refused)
        nativeRefusal <- runGit git (GitInvocation repo ["update-ref", "refs/heads/" ++ canonical nodeA, BSC.unpack (objectIdBytes b)] "" []) >>= expectRight
        assertTrue "Wrapped installed Hook allowed an invalid ref update" (gitExitCode nativeRefusal /= ExitSuccess)
        snapshot git repo >>= assertEqual before
        forM_ [["deploy", "--path", rootPath], ["node", "create", "--path", rootPath], ["--deploy-path", rootPath, "deploy"]] $ \args -> do
            rejected <- call wrapper repo args ""
            assertEqual (ExitFailure 2) (gitExitCode rejected)
        snapshot git repo >>= assertEqual before
        writeFile unusedFile "not a directory\n"
        forM_ [["check"], ["status", "-t", "node"], ["enable"], ["--help"], ["--version"]] $ \args -> do
            ignored <- call executable repo (["--deploy-path", unusedFile] ++ args) ""
            assertEqual ExitSuccess (gitExitCode ignored)
        invalid <- call executable repo ["--deploy-path", "relative", "deploy"] ""
        assertEqual (ExitFailure 2) (gitExitCode invalid)
        doesPathExist (repo </> "relative") >>= assertEqual False
        _ <- wrapped ["undeploy"]
        _ <- wrapped ["deploy"]
        doesDirectoryExist aPath >>= assertEqual True
        records <- listWorktrees git repo format >>= expectRight
        assertEqual 2 (length [record | record <- records, worktreeNode record /= Nothing])
        _ <- wrapped ["undeploy"]
        ignoredDisable <- call executable repo ["--deploy-path", unusedFile, "disable"] ""
        assertEqual ExitSuccess (gitExitCode ignoredDisable)
        readFile unusedFile >>= assertEqual "not a directory\n"
        snapshot git repo >>= assertEqual before

structuredLifecycle :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
structuredLifecycle git executable repo parent = do
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null"), ("GIT_AUTHOR_NAME", Just "Structured"), ("GIT_AUTHOR_EMAIL", Just "structured@example.invalid"), ("GIT_COMMITTER_NAME", Just "Structured"), ("GIT_COMMITTER_EMAIL", Just "structured@example.invalid")]
        call encoding location arguments = runGit (nativeGit executable) (GitInvocation location (["--format", encoding] ++ arguments) "" environment) >>= expectRight
        decode encoding bytes =
            if encoding == "json"
                then do
                    _ <- expectRight (Aeson.eitherDecodeStrict' bytes :: Either String Aeson.Value)
                    assertEqual 10 (BS.last bytes)
                else do
                    (remaining, _) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict bytes))
                    assertEqual BL.empty remaining
        success encoding location arguments = do
            response <- call encoding location arguments
            assertEqual ExitSuccess (gitExitCode response)
            decode encoding (gitStdout response)
            assertEqual BS.empty (gitStderr response)
        canonical = BSC.unpack . nodeIdBytes
    success "json" repo ["enable"]
    forM_ ["json", "cbor"] $ \encoding -> do
        success encoding repo ["check"]
        success encoding repo ["status", "-t", "node"]
        success encoding repo ["undeploy"]
        success encoding repo ["version"]
    success "json" repo ["disable"]
    root git repo nodeA
    root git repo nodeB
    success "cbor" repo ["enable"]
    -- Validate controlled fixture roots with the installed Hook.
    bRoot <- BSC.init <$> ok git repo ["rev-parse", canonical nodeB] ""
    bTree <- BSC.init <$> ok git repo ["rev-parse", canonical nodeB ++ "^{tree}"] ""
    bContent <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack bTree, "-p", BSC.unpack bRoot, "-m", "Historical B Content"] ""
    forM_ ["json", "cbor"] $ \encoding -> do
        success encoding repo ["deploy", "--path", parent </> "nodes"]
        success encoding repo ["status", "-t", "node"]
        blocked <- call encoding repo ["node", "delete", "--node", canonical nodeB, "--dry-run"]
        assertEqual (ExitFailure 1) (gitExitCode blocked)
        decode encoding (gitStdout blocked)
        warning <- call encoding repo ["checkpoint", "--node", canonical nodeA, "-m", "Machine checkpoint", "--context", canonical nodeB, "--context", BSC.unpack bContent]
        assertEqual ExitSuccess (gitExitCode warning)
        decode encoding (gitStdout warning)
        assertTrue "Structured warning is missing" ("multiple_context_versions" `BS.isInfixOf` gitStdout warning)
        assertEqual BS.empty (gitStderr warning)
        success encoding repo ["undeploy"]
        success encoding repo ["node", "delete", "--node", canonical nodeB, "--dry-run"]
        missing <- call encoding parent ["status", "-t", "node"]
        assertTrue "Repository discovery succeeded outside a repository" (gitExitCode missing /= ExitSuccess)
        assertEqual BS.empty (gitStdout missing)
        _ <- expectRight (Aeson.eitherDecodeStrict' (gitStderr missing) :: Either String Aeson.Value)
        pure ()
    preview <- call "json" repo ["node", "delete", "--node", canonical nodeB, "--dry-run"]
    value <- expectRight (Aeson.eitherDecodeStrict' (gitStdout preview) :: Either String Aeson.Value)
    fields <- case Aeson.fromJSON value :: Aeson.Result (Map.Map String Aeson.Value) of
        Aeson.Error message -> fail message
        Aeson.Success object -> pure object
    plan <- case Map.lookup "plan_id" fields of
        Just identifier -> case Aeson.fromJSON identifier :: Aeson.Result String of
            Aeson.Success identifierText -> pure identifierText
            Aeson.Error message -> fail message
        Nothing -> fail "Missing deletion plan"
    success "cbor" repo ["node", "delete", "--node", canonical nodeB, "--confirm", plan]
    success "cbor" repo ["disable"]
    _ <- ok git repo ["update-ref", "refs/heads/" ++ canonical nodeA, BSC.unpack bRoot] ""
    forM_ ["json", "cbor"] $ \encoding -> do
        invalid <- call encoding repo ["check"]
        assertEqual (ExitFailure 1) (gitExitCode invalid)
        decode encoding (gitStdout invalid)
        assertEqual BS.empty (gitStderr invalid)
