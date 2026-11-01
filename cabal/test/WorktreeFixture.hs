{-# LANGUAGE OverloadedStrings #-}

module WorktreeFixture (nodeA, nodeB, fixture, ok, root, snapshot, enable, manual) where

import Control.Monad (unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isPrefixOf)
import GitRoam.Application.Inspect (inspectState, reportManagedState)
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import System.Directory (createDirectory, findExecutable, makeAbsolute)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport

nodeA, nodeB :: NodeId
nodeA = either error id (parseNodeId "11111111-1111-4111-8111-111111111111")
nodeB = either error id (parseNodeId "22222222-2222-4222-8222-222222222222")

native :: Git IO
native = nativeGit defaultGitExecutable

fixture :: String -> ObjectFormat -> (Git IO -> FilePath -> FilePath -> FilePath -> IO ()) -> IO ()
fixture backend format action = withTempDirectory $ \parent -> do
    inherited <- getEnvironment
    let environment =
            [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
                ++ [ ("GIT_CONFIG_NOSYSTEM", Just "1")
                   , ("GIT_CONFIG_GLOBAL", Just "/dev/null")
                   , ("GIT_AUTHOR_NAME", Just "Fixture")
                   , ("GIT_AUTHOR_EMAIL", Just "fixture@example.invalid")
                   , ("GIT_COMMITTER_NAME", Just "Fixture")
                   , ("GIT_COMMITTER_EMAIL", Just "fixture@example.invalid")
                   ]
        git = Git $ \invocation -> runGit native invocation{gitEnvironment = environment ++ gitEnvironment invocation}
        repo = parent </> "repository"
    createDirectory repo
    _ <- ok git repo ["init", "-q", "--initial-branch=main", "--ref-format=" ++ backend, "--object-format=" ++ if format == Sha1 then "sha1" else "sha256"] ""
    executable <- findExecutable "git-roam" >>= maybe (fail "Cabal did not expose git-roam") makeAbsolute
    action git executable repo parent

ok :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO BS.ByteString
ok git directory arguments input = do
    result <- runGit git (GitInvocation directory arguments input []) >>= expectRight
    unless (gitExitCode result == ExitSuccess) (fail (show result))
    pure (gitStdout result)

root :: Git IO -> FilePath -> NodeId -> IO ()
root git repo node = do
    marker <- BSC.init <$> ok git repo ["hash-object", "-w", "--stdin"] ""
    inner <- BSC.init <$> ok git repo ["mktree"] ("100644 blob " <> marker <> "\t.roam\n")
    tree <- BSC.init <$> ok git repo ["mktree"] ("040000 tree " <> inner <> "\t" <> nodeIdBytes node <> "\n")
    commit <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack tree, "-m", "Root"] ""
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes node), BSC.unpack commit] ""
    pure ()

snapshot :: Git IO -> FilePath -> IO ManagedState
snapshot git repo = inspectState git repo [] Nothing >>= expectRight >>= expectRight . reportManagedState

enable :: Git IO -> FilePath -> FilePath -> IO ()
enable _ executable repo = do
    let cli = Git $ \invocation -> runGit (nativeGit executable) invocation
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
    -- No shell or test executable location is supplied by Nix.
    result <- runGit cli (GitInvocation repo ["enable"] "" environment) >>= expectRight
    unless (gitExitCode result == ExitSuccess) (fail (show result))

manual :: Git IO -> FilePath -> FilePath -> NodeId -> IO ()
manual git repo target node = do
    _ <- ok git repo ["worktree", "add", "--", target, BSC.unpack (nodeIdBytes node)] ""
    pure ()
