{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Map.Strict as Map
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Undeploy
import GitRoam.Cli (Command (..), HelpTopic (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import System.Directory (doesDirectoryExist, doesFileExist, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        [("undeploy CLI is whole-set and has no force/path options", arguments)]
            ++ [("undeploy retains refs and protection " ++ backend ++ " " ++ show format, fixture backend format lifecycle) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("unsafe second target prevents all removal", fixture "files" Sha1 dirtyPreflight)
               , ("ignored data and locked worktrees prevent all removal", fixture "files" Sha1 ignoredLocked)
               , ("main checkout is reported and never modified", fixture "files" Sha1 mainWorktree)
               , ("detached and ordinary linked worktrees are retained", fixture "files" Sha1 excludedWorktrees)
               , ("non-target nested worktree prevents all removal", fixture "files" Sha1 nestedConflict)
               , ("nested CLI invocation survives deletion of its directory", fixture "files" Sha1 removedCwd)
               , ("native removal failure stops and reports partial state", fixture "files" Sha1 partialFailure)
               , ("lost command result is not reported as success", fixture "files" Sha1 lostResult)
               , ("late user edits are retained without rollback", fixture "files" Sha1 lateEdits)
               , ("post-removal ref changes are diagnosed without reverting", fixture "files" Sha1 changedRefs)
               , ("invalid managed history refuses removal", fixture "files" Sha1 invalidState)
               , ("empty and repeated undeploy require protection", fixture "files" Sha1 emptyState)
               ]

arguments :: IO ()
arguments = do
    assertEqual (Right UndeployNodes) (parseCommand ["undeploy"])
    assertEqual (Right (ShowHelp UndeployHelp)) (parseCommand ["help", "undeploy"])
    forM_ [["undeploy", "--path", "work"], ["undeploy", "--node", BSC.unpack (nodeIdBytes nodeA)], ["undeploy", "--force"], ["undeploy", "--all"]] $ expectLeft . parseCommand

setup :: Git IO -> FilePath -> FilePath -> IO (FilePath, FilePath)
setup git repo parent = do
    root git repo nodeA
    root git repo nodeB
    let first = parent </> "a"; second = parent </> "b"
    manual git repo first nodeA
    manual git repo second nodeB
    pure (first, second)

hookConfig :: Git IO -> FilePath -> IO BS.ByteString
hookConfig git repo = ok git repo ["config", "--local", "--get-regexp", "^hook\\."] ""

lifecycle :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lifecycle git executable repo parent = do
    (first, second) <- setup git repo parent
    let moved = parent </> "moved"
    _ <- ok git repo ["worktree", "move", second, moved] ""
    enable git executable repo
    before <- snapshot git repo
    config <- hookConfig git repo
    report <- undeploy executable git repo >>= expectRight
    assertEqual 2 (length (removedWorktrees report))
    assertEqual [] (retainedMainNodes report)
    forM_ [first, moved] $ \path -> doesDirectoryExist path >>= assertEqual False
    snapshot git repo >>= assertEqual before
    hookConfig git repo >>= assertEqual config
    undeploy executable git repo >>= expectRight >>= assertEqual [] . removedWorktrees

dirtyPreflight :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyPreflight git executable repo parent = do
    (first, second) <- setup git repo parent
    enable git executable repo
    writeFile (second </> "user") "keep"
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist first >>= assertEqual True
    readFile (second </> "user") >>= assertEqual "keep"
    removeFile (second </> "user")
    writeFile (second </> BSC.unpack (nodeIdBytes nodeB) </> ".roam") "modified"
    _ <- ok git second ["add", "--all"] ""
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist first >>= assertEqual True

ignoredLocked :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
ignoredLocked git executable repo parent = do
    (first, second) <- setup git repo parent
    enable git executable repo
    writeFile (parent </> "excludes") "ignored\n"
    _ <- ok git repo ["config", "core.excludesFile", parent </> "excludes"] ""
    writeFile (second </> "ignored") "keep"
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist first >>= assertEqual True
    readFile (second </> "ignored") >>= assertEqual "keep"
    removeFile (second </> "ignored")
    _ <- ok git repo ["worktree", "lock", second] ""
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist first >>= assertEqual True

mainWorktree :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
mainWorktree git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
    let linked = parent </> "linked"
    manual git repo linked nodeB
    writeFile (repo </> "main-user-file") "keep"
    enable git executable repo
    report <- undeploy executable git repo >>= expectRight
    assertEqual 1 (length (removedWorktrees report))
    assertEqual [nodeA] (map fst (retainedMainNodes report))
    readFile (repo </> "main-user-file") >>= assertEqual "keep"
    doesFileExist (repo </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") >>= assertEqual True
    _ <- snapshot git repo
    pure ()

excludedWorktrees :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
excludedWorktrees git executable repo parent = do
    root git repo nodeA
    let linked = parent </> "node"; detached = parent </> "detached"; ordinary = parent </> "ordinary"
    manual git repo linked nodeA
    _ <- ok git repo ["worktree", "add", "--detach", detached, BSC.unpack (nodeIdBytes nodeA)] ""
    _ <- ok git repo ["worktree", "add", "-b", "ordinary", ordinary, BSC.unpack (nodeIdBytes nodeA)] ""
    writeFile (detached </> "user") "keep"
    enable git executable repo
    undeploy executable git repo >>= expectRight >>= assertEqual 1 . length . removedWorktrees
    forM_ [detached, ordinary] $ \path -> doesDirectoryExist path >>= assertEqual True
    readFile (detached </> "user") >>= assertEqual "keep"

nestedConflict :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nestedConflict git executable repo parent = do
    root git repo nodeA
    let linked = parent </> "node"
    manual git repo linked nodeA
    _ <- ok git repo ["worktree", "add", "--detach", linked </> "detached", BSC.unpack (nodeIdBytes nodeA)] ""
    enable git executable repo
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist linked >>= assertEqual True

cli :: FilePath -> FilePath -> [String] -> IO GitResult
cli executable directory args = do
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
    runGit (nativeGit executable) (GitInvocation directory args "" environment) >>= expectRight

removedCwd :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
removedCwd git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    let outer = parent </> "outer"; inner = outer </> "nested" </> "inner"
    manual git repo outer nodeA
    manual git repo inner nodeB
    enable git executable repo
    before <- snapshot git repo
    result <- cli executable (inner </> BSC.unpack (nodeIdBytes nodeB)) ["undeploy"]
    assertEqual ExitSuccess (gitExitCode result)
    assertTrue "Missing count" ("Undeployed 2" `BS.isInfixOf` gitStdout result)
    doesDirectoryExist outer >>= assertEqual False
    snapshot git repo >>= assertEqual before
    disabled <- cli executable repo ["disable"]
    assertEqual ExitSuccess (gitExitCode disabled)

isRemove :: GitInvocation -> Bool
isRemove invocation = "worktree" `elem` gitArguments invocation && "remove" `elem` gitArguments invocation

partialFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
partialFailure git executable repo parent = do
    (first, second) <- setup git repo parent
    enable git executable repo
    before <- snapshot git repo
    let failing = Git $ \invocation ->
            if isRemove invocation && second `elem` gitArguments invocation
                then pure (Right (GitResult (ExitFailure 1) "" "fixture native failure"))
                else runGit git invocation
    result <- undeploy executable failing repo
    case result of
        Left (UndeploymentFailure reason details) -> do
            assertTrue "Lost native failure" ("fixture native failure" `isInfixOf` reason)
            assertTrue "Lost residual report" (any (isInfixOf "Remaining Node worktrees") details)
        Right value -> fail (show value)
    doesDirectoryExist first >>= assertEqual False
    doesDirectoryExist second >>= assertEqual True
    snapshot git repo >>= assertEqual before

lostResult :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lostResult git executable repo parent = do
    (first, second) <- setup git repo parent
    enable git executable repo
    let failing = Git $ \invocation -> do
            result <- runGit git invocation
            if isRemove invocation && second `elem` gitArguments invocation
                then pure (Right (GitResult (ExitFailure 1) "" "fixture lost completion"))
                else pure result
    undeploy executable failing repo >>= expectLeft
    forM_ [first, second] $ \path -> doesDirectoryExist path >>= assertEqual False
    _ <- snapshot git repo
    pure ()

lateEdits :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lateEdits git executable repo parent = do
    (first, second) <- setup git repo parent
    enable git executable repo
    let racing = Git $ \invocation -> do
            if isRemove invocation && first `elem` gitArguments invocation
                then writeFile (second </> "late-user-file") "keep"
                else pure ()
            runGit git invocation
    undeploy executable racing repo >>= expectLeft
    doesDirectoryExist first >>= assertEqual False
    readFile (second </> "late-user-file") >>= assertEqual "keep"
    _ <- snapshot git repo
    pure ()

invalidState :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidState git executable repo parent = do
    root git repo nodeA
    let linked = parent </> "node"
    manual git repo linked nodeA
    a <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeA)] ""
    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), BSC.unpack a]) ""
    enable git executable repo
    undeploy executable git repo >>= expectLeft
    doesDirectoryExist linked >>= assertEqual True

changedRefs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
changedRefs git executable repo parent = do
    (_, second) <- setup git repo parent
    let branch = BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB)
    old <- BSC.init <$> ok git repo ["rev-parse", branch] ""
    tree <- BSC.init <$> ok git repo ["rev-parse", branch ++ "^{tree}"] ""
    edited <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack tree, "-p", BSC.unpack old, "-m", "Uncoordinated Content"] ""
    enable git executable repo
    let racing = Git $ \invocation -> do
            result <- runGit git invocation
            if isRemove invocation && second `elem` gitArguments invocation
                then do
                    -- Model an external writer outside the application lock.
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", branch, BSC.unpack edited, BSC.unpack old]) ""
                    pure result
                else pure result
    undeploy executable racing repo >>= expectLeft
    actual <- BSC.init <$> ok git repo ["rev-parse", branch] ""
    assertEqual edited actual
    _ <- snapshot git repo
    pure ()

emptyState :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
emptyState git executable repo _ = do
    undeploy executable git repo >>= expectLeft
    enable git executable repo
    forM_ [1 :: Int, 2] $ \_ -> undeploy executable git repo >>= expectRight >>= assertEqual [] . removedWorktrees
    snapshot git repo >>= assertEqual Map.empty . managedRefs
