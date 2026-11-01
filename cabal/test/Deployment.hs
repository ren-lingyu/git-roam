{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import GitRoam.Application.Deploy
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Cli (Command (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Worktree.Paths (shortName)
import System.Directory (createDirectory, doesDirectoryExist, doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        [("deploy CLI requires path and rejects subset selection", cliArguments)]
            ++ [("fetch/deploy tracking and closure " ++ backend ++ " " ++ show format, fixture backend format batch) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("ordinary clone followed by CLI enable/deploy", fixture "files" Sha1 cloneFlow)
               , ("equivalent remote sources coalesce", fixture "files" Sha1 equalSources)
               , ("divergent candidates need explicit remote; locals never advance", fixture "files" Sha1 ambiguity)
               , ("deployment can complete initially missing dependency branches", fixture "files" Sha1 repairClosure)
               , ("incomplete or invalid targets refuse all writes", fixture "files" Sha1 invalidTargets)
               , ("unsafe deployment root refuses before branch creation", fixture "files" Sha1 unsafeRoot)
               , ("failed checkout compensates clean newly created state", fixture "files" Sha1 cleanFailure)
               , ("user changes retain new branch and required dependencies", fixture "files" Sha1 dirtyFailure)
               , ("conditional transaction refuses stale existing refs", fixture "files" Sha1 racingRefs)
               , ("compensation preserves refs created by another transaction", fixture "files" Sha1 competingCreation)
               , ("empty deployment and protection prerequisite", fixture "files" Sha1 emptyDeployment)
               ]

cliArguments :: IO ()
cliArguments = do
    assertEqual (Right (DeployNodes "work" Nothing)) (parseCommand ["deploy", "--path", "work"])
    assertEqual (Right (DeployNodes "work" (Just "origin"))) (parseCommand ["deploy", "--remote", "origin", "--path", "work"])
    forM_ [["deploy"], ["deploy", "--path", ""], ["deploy", "--path", "--remote"], ["deploy", "--path", "work", "--node", BSC.unpack (nodeIdBytes nodeA)], ["deploy", "--path", "work", "--path", "again"]] $ expectLeft . parseCommand

commit :: Git IO -> FilePath -> BS.ByteString -> [BS.ByteString] -> IO BS.ByteString
commit git directory tree parents = BSC.init <$> ok git directory (["commit-tree", BSC.unpack tree, "-m", "Fixture"] ++ concatMap (\p -> ["-p", BSC.unpack p]) parents) ""

tip :: Git IO -> FilePath -> NodeId -> IO BS.ByteString
tip git directory node = BSC.init <$> ok git directory ["rev-parse", BSC.unpack (nodeIdBytes node)] ""

checkpoint :: Git IO -> FilePath -> NodeId -> [BS.ByteString] -> IO BS.ByteString
checkpoint git directory node dependencies = do
    base <- tip git directory node
    tree <- BSC.init <$> ok git directory ["rev-parse", BSC.unpack (nodeIdBytes node) ++ "^{tree}"] ""
    content <- commit git directory tree [base]
    version <- commit git directory tree (base : content : dependencies)
    _ <- ok git directory ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes node), BSC.unpack version] ""
    pure version

source :: Git IO -> FilePath -> FilePath -> IO FilePath
source git repo parent = do
    format <- BSC.init <$> ok git repo ["rev-parse", "--show-object-format"] ""
    let directory = parent </> "source"
    createDirectory directory
    _ <- ok git directory ["init", "-q", "--initial-branch=main", "--object-format=" ++ BSC.unpack format] ""
    root git directory nodeA
    root git directory nodeB
    b <- checkpoint git directory nodeB []
    a <- checkpoint git directory nodeA [b]
    _ <- checkpoint git directory nodeB [a]
    tree <- BSC.init <$> ok git directory ["mktree"] ""
    mainTip <- commit git directory tree []
    _ <- ok git directory ["update-ref", "refs/heads/main", BSC.unpack mainTip] ""
    pure directory

fetch :: Git IO -> FilePath -> String -> FilePath -> IO ()
fetch git repo remote directory = do
    _ <- ok git repo ["remote", "add", remote, directory] ""
    _ <- ok git repo ["fetch", "--quiet", remote] ""
    pure ()

refs :: Git IO -> FilePath -> IO BS.ByteString
refs git repo = ok git repo ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"] ""

batch :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
batch git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    enable git executable repo
    report <- deploy executable git repo (parent </> "deployed") Nothing >>= expectRight
    assertEqual 2 (length (deployedWorktrees report))
    assertEqual 2 (length (trackingSources report))
    forM_ [nodeA, nodeB] $ \node -> do
        upstreamRef <- ok git repo ["for-each-ref", "--format=%(upstream)", BSC.unpack ("refs/heads/" <> nodeIdBytes node)] ""
        assertEqual ("refs/remotes/origin/" <> nodeIdBytes node <> "\n") upstreamRef
        expected <- tip git upstream node
        tip git repo node >>= assertEqual expected
    first <- snapshot git repo
    again <- deploy executable git repo (parent </> "another") Nothing >>= expectRight
    assertEqual (deployedWorktrees report) (deployedWorktrees again)
    snapshot git repo >>= assertEqual first
    doesDirectoryExist (parent </> "another") >>= assertEqual False

cli :: FilePath -> FilePath -> [String] -> IO GitResult
cli executable directory args = do
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null"), ("GIT_ALLOW_PROTOCOL", Just "file")]
    runGit (nativeGit executable) (GitInvocation directory args "" environment) >>= expectRight

cloneFlow :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cloneFlow git executable repo parent = do
    upstream <- source git repo parent
    let cloned = parent </> "clone"
    _ <- ok git parent ["clone", "--quiet", upstream, cloned] ""
    result <- cli executable cloned ["enable"]
    assertEqual ExitSuccess (gitExitCode result)
    writeFile (cloned </> ".gitignore") "/work/\n"
    deployed <- cli executable cloned ["deploy", "--path", "work"]
    assertEqual ExitSuccess (gitExitCode deployed)
    assertTrue "Missing deployed count" ("Deployed 2 Nodes." `BS.isInfixOf` gitStdout deployed)
    doesFileExist (cloned </> "work" </> shortName nodeA </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") >>= assertEqual True
    checked <- cli executable cloned ["check"]
    assertEqual ExitSuccess (gitExitCode checked)

equalSources :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
equalSources git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    fetch git repo "backup" upstream
    _ <- ok git repo ["config", "checkout.defaultRemote", "origin"] ""
    enable git executable repo
    report <- deploy executable git repo (parent </> "work") Nothing >>= expectRight
    assertEqual 2 (length (trackingSources report))
    _ <- snapshot git repo
    pure ()

ambiguity :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
ambiguity git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    _ <- checkpoint git upstream nodeA []
    fetch git repo "backup" upstream
    _ <- ok git repo ["config", "checkout.defaultRemote", "backup"] ""
    enable git executable repo
    before <- refs git repo
    deploy executable git repo (parent </> "work") Nothing >>= expectLeft
    refs git repo >>= assertEqual before
    _ <- deploy executable git repo (parent </> "work") (Just "origin") >>= expectRight
    old <- tip git repo nodeA
    _ <- ok git repo ["fetch", "--quiet", "origin"] ""
    _ <- deploy executable git repo (parent </> "other") Nothing >>= expectRight
    tip git repo nodeA >>= assertEqual old
    deploy executable git repo (parent </> "other") (Just "unknown") >>= expectLeft

repairClosure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
repairClosure git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    a <- tip git upstream nodeA
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack a] ""
    enable git executable repo
    _ <- deploy executable git repo (parent </> "work") Nothing >>= expectRight
    _ <- snapshot git repo
    pure ()

invalidTargets :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidTargets git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    b <- tip git upstream nodeB
    _ <- ok git repo ["update-ref", "-d", BSC.unpack ("refs/remotes/origin/" <> nodeIdBytes nodeB)] ""
    enable git executable repo
    before <- refs git repo
    deploy executable git repo (parent </> "work") Nothing >>= expectLeft
    refs git repo >>= assertEqual before
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/remotes/origin/" <> nodeIdBytes nodeA), BSC.unpack b] ""
    deploy executable git repo (parent </> "work") Nothing >>= expectLeft
    refs git repo >>= assertEqual before

unsafeRoot :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
unsafeRoot git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    enable git executable repo
    let path = parent </> "work"
    createDirectory path
    writeFile (path </> "user") "keep"
    before <- refs git repo
    deploy executable git repo path Nothing >>= expectLeft
    refs git repo >>= assertEqual before
    readFile (path </> "user") >>= assertEqual "keep"

failureHook :: Git IO -> FilePath -> String -> IO ()
failureHook git repo script = do
    _ <- ok git repo ["config", "hook.fail-deploy.event", "post-checkout"] ""
    _ <- ok git repo ["config", "hook.fail-deploy.command", script] ""
    pure ()

cleanFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cleanFailure git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    enable git executable repo
    failureHook git repo "false"
    before <- refs git repo
    deploy executable git repo (parent </> "work") Nothing >>= expectLeft
    refs git repo >>= assertEqual before
    state <- snapshot git repo
    assertEqual Map.empty (managedRefs state)
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual 1 (length records)
    forM_ [nodeA, nodeB] $ \node -> do
        result <- runGit git (GitInvocation repo ["config", "--local", "--get-regexp", "^branch\\." ++ BSC.unpack (nodeIdBytes node) ++ "\\."] "" []) >>= expectRight
        assertEqual (ExitFailure 1) (gitExitCode result)

dirtyFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyFailure git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    enable git executable repo
    let path = parent </> "work"; userFile = path </> shortName nodeA </> "user-file"
    failureHook git repo ("printf user > '" ++ userFile ++ "'; false")
    deploy executable git repo path Nothing >>= expectLeft
    readFile userFile >>= assertEqual "user"
    state <- snapshot git repo
    assertEqual 2 (Map.size (managedRefs state))
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual 1 (length [r | r <- records, worktreeNode r /= Nothing])

racingRefs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
racingRefs git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    a <- tip git upstream nodeA
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack a] ""
    tree <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack a ++ "^{tree}"] ""
    edited <- commit git repo tree [a]
    enable git executable repo
    let racing = Git $ \invocation -> do
            if "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation
                then do
                    -- Deliberately uncoordinated external writer: bypass only
                    -- the fixture's own Hook to exercise expected-old refusal.
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack edited, BSC.unpack a]) ""
                    runGit git invocation
                else runGit git invocation
    deploy executable racing repo (parent </> "work") Nothing >>= expectLeft
    tip git repo nodeA >>= assertEqual edited
    result <- runGit git (GitInvocation repo ["show-ref", "--verify", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB)] "" []) >>= expectRight
    assertTrue "Racing transaction partially created B" (gitExitCode result /= ExitSuccess)

emptyDeployment :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
emptyDeployment git executable repo parent = do
    deploy executable git repo (parent </> "work") Nothing >>= expectLeft
    enable git executable repo
    report <- deploy executable git repo (parent </> "work") Nothing >>= expectRight
    assertEqual [] (deployedWorktrees report)
    doesDirectoryExist (parent </> "work") >>= assertEqual False

competingCreation :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingCreation git executable repo parent = do
    upstream <- source git repo parent
    fetch git repo "origin" upstream
    enable git executable repo
    let racing = Git $ \invocation -> do
            if "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation
                then do
                    -- Another transaction wins with the same complete target.
                    _ <- runGit git invocation >>= expectRight
                    runGit git invocation
                else runGit git invocation
    deploy executable racing repo (parent </> "work") Nothing >>= expectLeft
    state <- snapshot git repo
    assertEqual 2 (Map.size (managedRefs state))
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual 1 (length records)
