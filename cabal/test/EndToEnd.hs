{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Directory (doesDirectoryExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

main :: IO ()
main = runTests [("public CLI lifecycle and native synchronization " ++ backend ++ " " ++ show format, fixture backend format (lifecycle backend format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

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
        reject location args = do
            result <- call location args
            assertEqual (ExitFailure 1) (gitExitCode result)
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
    bPath <- edit repo b "* B version zero\n"
    b0 <- roam bPath ["checkpoint", "-m", "Confirm B0"] >>= checkpointFrom
    aPath <- edit repo a "* A uses B0\n"
    a0 <- roam aPath ["checkpoint", "-m", "Confirm A0", "--depend", oid b0] >>= checkpointFrom
    _ <- edit repo b "* B version one\n"
    b1 <- roam bPath ["checkpoint", "-m", "Confirm B1"] >>= checkpointFrom
    source <- snapshot git repo
    version <- expectRight (projectCheckpoint (managedHistory source) a0) >>= maybe (fail "No formal A version") pure
    assertEqual (Map.singleton b b0) (versionDependencies version)
    assertTrue "Exact old dependency not retained" (Set.member b0 (retainedCheckpoints source Map.! b))
    check repo
    _ <- roam aPath ["status"]

    -- Clone transports objects/refs, enable installs protection independently,
    -- and deploy establishes the complete missing local tracking-branch set.
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
    assertEqual (retainedCheckpoints source) (retainedCheckpoints copied)
    forM_ [a, b] $ \node -> do
        upstream <- ok git clone ["config", "--get", "branch." ++ uuid node ++ ".merge"] ""
        assertEqual (BSC.pack (branch node) <> "\n") upstream
    check clone

    -- The source adds one formal version. Fetch and deploy leave an existing
    -- local branch untouched; native --ff-only updates its deployed index/tree.
    _ <- edit repo b "* B version two\n"
    b2 <- roam bPath ["checkpoint", "-m", "Confirm B2"] >>= checkpointFrom
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
    retained <- snapshot git clone
    assertTrue "Native advancement lost prior formal version" (Set.member b1 (retainedCheckpoints retained Map.! b))

    -- A later source snapshot needs two local branch advances together. The
    -- public Hook validates the complete native transaction without bypass.
    _ <- edit repo b "* B version three\n"
    b3 <- roam bPath ["checkpoint", "-m", "Confirm B3"] >>= checkpointFrom
    a1 <- roam aPath ["checkpoint", "-m", "A now uses B3", "--depend", oid b3] >>= checkpointFrom
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

    -- Deletion cannot hide a dependency. Explicit discard removes precisely
    -- B0's retained formal successors and A0, leaving each identity at Root.
    reject clone ["node", "delete", "--node", uuid b, "--dry-run"]
    plan <- roam clone ["discard", "--dry-run", oid b0] >>= field "plan"
    _ <- roam clone ["discard", "--confirm", BSC.unpack plan, oid b0]
    discarded <- snapshot git clone
    assertEqual (Map.fromList [(a, Set.empty), (b, Set.empty)]) (retainedCheckpoints discarded)
    original <- snapshot git repo
    assertEqual (Just b3) (Map.lookup b (managedRefs original))
    assertEqual (Just a1) (Map.lookup a (managedRefs original))
    reject clone ["node", "delete", "--node", uuid b, "--dry-run"]
    _ <- roam clone ["undeploy"]
    confirmDelete clone a
    confirmDelete clone b
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
