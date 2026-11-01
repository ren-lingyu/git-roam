{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import GitRoam.Application.Worktree
import GitRoam.Git
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Worktree.Paths
import System.Directory (createDirectory, doesDirectoryExist, removeDirectory, removeDirectoryRecursive, removeFile)
import System.FilePath
import qualified System.Posix.Files as Files
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        [ ("fixed short-name vectors and collision rejection", names)
        , ("NUL worktree parser preserves byte paths and states", parser)
        , ("filesystem path round-trip and symlink refusal", paths)
        , ("nested deployment requires complete ignore protection", fixture "files" Sha1 nestedRoot)
        , ("existing moved and dirty deployments are preserved", fixture "files" Sha1 moved)
        , ("all removal targets are preflighted for user data", fixture "files" Sha1 dirty)
        , ("stale worktree and ref plans refuse mutation", fixture "files" Sha1 stale)
        , ("nested target removal is ordered and preserves refs", fixture "files" Sha1 nestedRemoval)
        , ("non-target nested worktree blocks removal", fixture "files" Sha1 foreignNested)
        , ("main, locked and prunable worktrees are protected", fixture "files" Sha1 specialStates)
        , ("other Hook failure reports residual state", fixture "files" Sha1 failedAdd)
        ]
            ++ [("protected primitives " ++ backend ++ " " ++ show format, fixture backend format lifecycle) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

names :: IO ()
names = do
    assertEqual "xv3gfjpo" (shortName nodeA)
    assertEqual "wrkpqlcy" (shortName nodeB)
    expectLeft (checkPathCollisions [(nodeA, "/same"), (nodeB, "/same")])
    expectRight (checkPathCollisions [(nodeA, "/a"), (nodeB, "/b")])

parser :: IO ()
parser = do
    let oid = BS.replicate 40 49
        record path fields = "worktree " <> path <> "\0" <> BS.intercalate "\0" fields <> "\0\0"
        mainRecord = record "/main" ["HEAD " <> BS.replicate 40 48, "branch refs/heads/main"]
        rawPath = "/newline\n" <> BS.pack [255]
        linked = record rawPath ["HEAD " <> oid, "branch refs/heads/" <> nodeIdBytes nodeA, "locked reason\nline", "prunable gone"]
    records <- expectRight (decodeWorktrees Sha1 (mainRecord <> linked))
    assertEqual [True, False] (map treeMain records)
    assertEqual [Nothing] (map treeHead (take 1 records))
    assertEqual rawPath (treePath (records !! 1))
    assertEqual (Just nodeA) (worktreeNode (records !! 1))
    assertEqual (Just "reason\nline") (treeLocked (records !! 1))
    _ <- expectRight (decodeWorktrees Sha1 (record "/bare" ["bare"] <> record "/detached" ["HEAD " <> oid, "detached"]))
    forM_ [BS.init linked, linked <> linked, record "/bad" ["HEAD " <> oid, "detached", "branch refs/heads/main"], record "/bad" ["HEAD " <> oid, "HEAD " <> oid, "detached"], record "/bad" ["HEAD " <> oid, "mystery"]] $ expectLeft . decodeWorktrees Sha1

paths :: IO ()
paths = withTempDirectory $ \parent -> do
    let raw = "/path/" <> BS.pack [255, 10, 195, 169]
    decodePath raw >>= encodePath >>= assertEqual raw
    let target = parent </> "link"
    Files.createSymbolicLink "/missing" target
    safeAbsolutePath (target </> ".." </> "escape") >>= expectLeft
    safeAbsolutePath (target </> "child") >>= expectLeft
    safeAbsolutePath "" >>= expectLeft
    safeAbsolutePath (parent </> "missing" </> "child") >>= expectRight >>= assertEqual (parent </> "missing" </> "child")

lifecycle :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lifecycle git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    state <- snapshot git repo
    let deployment = parent </> "deployed\nspace"
    plan <- planDeployment git repo state deployment >>= expectRight
    assertEqual 2 (length (pendingDeployments plan))
    withProtectedSession executable git repo (\_ -> pure (Right ())) >>= expectLeft
    enable git executable repo
    withProtectedSession
        executable
        git
        repo
        ( \session -> do
            first <- addPlannedWorktree session plan nodeA
            case first of Left problem -> pure (Left problem); Right () -> addPlannedWorktree session plan nodeB
        )
        >>= expectRight
    after <- planDeployment git repo state deployment >>= expectRight
    assertEqual [] (pendingDeployments after)
    assertEqual 2 (Map.size (existingDeployments after))
    removal <- planRemoval git repo state >>= expectRight
    withProtectedSession executable git repo (\session -> removeAll session removal) >>= expectRight
    planRemoval git repo state >>= expectRight >>= assertEqual [] . removalTargets
    snapshot git repo >>= assertEqual state
  where
    removeAll session plan = do
        outcomes <- mapM (\r -> removePlannedWorktree session plan (maybe (error "missing Node") id (worktreeNode r))) (removalTargets plan)
        pure (sequence_ outcomes)

nestedRoot :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nestedRoot git _ repo parent = do
    root git repo nodeA
    state <- snapshot git repo
    planDeployment git repo state (repo </> "unignored") >>= expectLeft
    writeFile (repo </> ".gitignore") "/deployment/\n"
    _ <- planDeployment git repo state (repo </> "deployment") >>= expectRight
    planDeployment git repo state repo >>= expectLeft
    planDeployment git repo state (repo </> ".git" </> "data") >>= expectLeft
    let unrelated = parent </> "unrelated"
    createDirectory unrelated
    writeFile (unrelated </> "keep") "user"
    planDeployment git repo state unrelated >>= expectLeft
    _ <- ok git repo ["add", "-f", "--", ".gitignore"] ""
    createDirectory (repo </> "deployment")
    writeFile (repo </> "deployment" </> "tracked") "keep"
    _ <- ok git repo ["add", "-f", "--", "deployment/tracked"] ""
    planDeployment git repo state (repo </> "deployment") >>= expectLeft

moved :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
moved git _ repo parent = do
    root git repo nodeA
    let original = parent </> "manual"; target = parent </> "moved"
    manual git repo original nodeA
    _ <- ok git repo ["worktree", "move", "--", original, target] ""
    writeFile (target </> "user-file") "keep"
    state <- snapshot git repo
    plan <- planDeployment git repo state (parent </> "another-root") >>= expectRight
    assertEqual (Just target) (Map.lookup nodeA (existingDeployments plan))
    assertEqual [] (pendingDeployments plan)
    planRemoval git repo state >>= expectLeft

dirty :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirty git _ repo parent = do
    root git repo nodeA
    let target = parent </> "manual"; marker = target </> BSC.unpack (nodeIdBytes nodeA) </> ".roam"
    manual git repo target nodeA
    state <- snapshot git repo
    let refuse = planRemoval git repo state >>= expectLeft
    writeFile marker "changed"
    refuse
    _ <- ok git target ["add", "--all"] ""
    refuse
    _ <- ok git target ["reset", "--hard", "HEAD"] ""
    writeFile (target </> "untracked") "keep"
    refuse
    removeFile (target </> "untracked")
    _ <- ok git repo ["config", "core.excludesFile", parent </> "excludes"] ""
    writeFile (parent </> "excludes") "ignored\n"
    writeFile (target </> "ignored") "keep"
    refuse
    removeFile (target </> "ignored")
    createDirectory (target </> "empty")
    refuse
    removeDirectory (target </> "empty")
    Files.createNamedPipe (target </> "pipe") 0o600
    refuse
    removeFile (target </> "pipe")
    _ <- ok git target ["update-index", "--assume-unchanged", BSC.unpack (nodeIdBytes nodeA) </> ".roam"] ""
    refuse
    _ <- ok git target ["update-index", "--no-assume-unchanged", BSC.unpack (nodeIdBytes nodeA) </> ".roam"] ""
    _ <- ok git target ["update-index", "--skip-worktree", BSC.unpack (nodeIdBytes nodeA) </> ".roam"] ""
    refuse
    _ <- ok git target ["update-index", "--no-skip-worktree", BSC.unpack (nodeIdBytes nodeA) </> ".roam"] ""
    mergePath <- BSC.init <$> ok git target ["rev-parse", "--git-path", "MERGE_HEAD"] ""
    decoded <- decodePath mergePath
    writeFile decoded "in-progress"
    refuse
    removeFile decoded
    _ <- planRemoval git repo state >>= expectRight
    pure ()

stale :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
stale git executable repo parent = do
    root git repo nodeA
    state <- snapshot git repo
    plan <- planDeployment git repo state (parent </> "deploy") >>= expectRight
    root git repo nodeB
    enable git executable repo
    withProtectedSession executable git repo (\session -> addPlannedWorktree session plan nodeA) >>= expectLeft
    state2 <- snapshot git repo
    let target = parent </> "manual"
    manual git repo target nodeA
    removal <- planRemoval git repo state2 >>= expectRight
    writeFile (target </> "new-user-file") "keep"
    withProtectedSession executable git repo (\session -> removePlannedWorktree session removal nodeA) >>= expectLeft
    readFile (target </> "new-user-file") >>= assertEqual "keep"

nestedRemoval :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nestedRemoval git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    let outer = parent </> "outer"; inner = outer </> "nested" </> "inner"
    manual git repo outer nodeA
    manual git repo inner nodeB
    state <- snapshot git repo
    plan <- planRemoval git repo state >>= expectRight
    assertEqual [Just nodeB, Just nodeA] (map worktreeNode (removalTargets plan))
    enable git executable repo
    withProtectedSession
        executable
        git
        repo
        ( \session -> do
            early <- removePlannedWorktree session plan nodeA
            expectLeft early
            b <- removePlannedWorktree session plan nodeB
            case b of Left problem -> pure (Left problem); Right () -> removePlannedWorktree session plan nodeA
        )
        >>= expectRight
    doesDirectoryExist outer >>= assertEqual False

foreignNested :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
foreignNested git _ repo parent = do
    root git repo nodeA
    let target = parent </> "outer"
    manual git repo target nodeA
    _ <- ok git repo ["worktree", "add", "--detach", "--", target </> "detached", BSC.unpack (nodeIdBytes nodeA)] ""
    state <- snapshot git repo
    planRemoval git repo state >>= expectLeft

specialStates :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
specialStates git _ repo parent = do
    root git repo nodeA
    let target = parent </> "manual"
    manual git repo target nodeA
    state <- snapshot git repo
    _ <- ok git repo ["worktree", "lock", target] ""
    planRemoval git repo state >>= expectLeft
    planDeployment git repo state (parent </> "deploy") >>= expectLeft
    _ <- ok git repo ["worktree", "unlock", target] ""
    removeDirectoryRecursive target
    planRemoval git repo state >>= expectLeft
    _ <- ok git repo ["worktree", "prune"] ""
    _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
    planDeployment git repo state (parent </> "deploy") >>= expectLeft
    planRemoval git repo state >>= expectRight >>= assertEqual 1 . length . retainedMainWorktrees

failedAdd :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
failedAdd git executable repo parent = do
    root git repo nodeA
    state <- snapshot git repo
    plan <- planDeployment git repo state (parent </> "deploy") >>= expectRight
    enable git executable repo
    _ <- ok git repo ["config", "hook.fixture-checkout.event", "post-checkout"] ""
    _ <- ok git repo ["config", "hook.fixture-checkout.command", "false"] ""
    withProtectedSession executable git repo (\session -> addPlannedWorktree session plan nodeA) >>= expectLeft
    snapshot git repo >>= assertEqual state
    after <- planDeployment git repo state (parent </> "deploy") >>= expectRight
    assertEqual 1 (Map.size (existingDeployments after))
