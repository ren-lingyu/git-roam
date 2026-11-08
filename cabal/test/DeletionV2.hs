{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified GitRoam.Application.V2.Checkpoint as Checkpoints
import qualified GitRoam.Application.V2.Delete as Deletion
import qualified GitRoam.Application.V2.Inspect as Inspection
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.V2.History
import GitRoam.Protocol.V2.Repository
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture (enable, fixture, manual, nodeA, nodeB, ok, root)

ref :: NodeId -> String
ref node = "refs/heads/" ++ BSC.unpack (nodeIdBytes node)

revision :: ObjectId -> String
revision = BSC.unpack . objectIdBytes

tip :: Git IO -> FilePath -> NodeId -> IO ObjectId
tip git directory node = do
    format <- BSC.init <$> ok git directory ["rev-parse", "--show-object-format=storage"] "" >>= expectRight . parseObjectFormat
    bytes <- BSC.init <$> ok git directory ["rev-parse", ref node] ""
    expectRight (parseObjectId format bytes)

makeContent :: Git IO -> FilePath -> NodeId -> IO ObjectId
makeContent git directory node = do
    old <- tip git directory node
    tree <- BSC.init <$> ok git directory ["rev-parse", revision old ++ "^{tree}"] ""
    bytes <- BSC.init <$> ok git directory ["commit-tree", BSC.unpack tree, "-p", revision old, "-m", "Editable Content"] ""
    format <- BSC.init <$> ok git directory ["rev-parse", "--show-object-format=storage"] "" >>= expectRight . parseObjectFormat
    new <- expectRight (parseObjectId format bytes)
    _ <- ok git directory ["update-ref", ref node, revision new, revision old] ""
    pure new

current :: Git IO -> FilePath -> IO ManagedState
current git directory = do
    report <- Inspection.inspectState git directory [] Nothing >>= expectRight
    assertEqual [] (Inspection.reportProblems report)
    expectRight (Inspection.reportManagedState report)

main :: IO ()
main =
    runTests $
        [ ("v2 deletion rejects checked-out worktrees", fixture "files" Sha1 checkedOut)
        , ("v2 deletion verifies confirmation and branch configuration", fixture "files" Sha1 configuration)
        , ("v2 deletion refuses stale plans after ref changes", fixture "files" Sha1 stalePlan)
        , ("v2 deletion respects other named Git Hooks", fixture "files" Sha1 otherHook)
        ]
            ++ [ ("v2 non-cascading deletion " ++ backend ++ " " ++ show format, fixture backend format nonCascading)
               | backend <- ["files", "reftable"]
               , format <- [Sha1, Sha256]
               ]

nonCascading :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nonCascading git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    b <- tip git directory nodeB
    bContent <- makeContent git directory nodeB
    enable git executable directory
    checkpoint <- Checkpoints.checkpoint executable git directory nodeA "A remembers B Root" [revision b] >>= expectRight
    -- The old dependency-closure rule would prohibit deleting B while A's
    -- current Checkpoint points to it. Context-only history must permit it.
    preview <- Deletion.previewDelete git directory nodeB >>= expectRight
    assertEqual [] (Deletion.deleteProblems preview)
    assertEqual (Set.singleton bContent) (Deletion.deleteExclusiveCommits preview)
    token <- maybe (fail "Missing deletion plan") pure (Deletion.deletePlanId preview)
    deleted <- Deletion.executeDelete executable git directory nodeB token >>= expectRight
    assertEqual preview deleted
    state <- current git directory
    assertEqual (Map.singleton nodeA (Checkpoints.checkpointOid checkpoint)) (managedRefs state)
    let history = managedHistory state
    retained <- expectRight (reachableHistory history (Checkpoints.checkpointOid checkpoint))
    assertTrue "Context object lost after deleting its Node branch" (Set.member b retained)
    -- A second execution cannot quietly delete another Node or create an
    -- invalid state just because the original confirmation token is reused.
    Deletion.executeDelete executable git directory nodeB token >>= expectLeft
    current git directory >>= assertEqual state

checkedOut :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
checkedOut git executable directory parent = do
    root git directory nodeA
    enable git executable directory
    let path = parent </> "checked-out-node"
    manual git directory path nodeA
    report <- Deletion.previewDelete git directory nodeA >>= expectRight
    unless (not (null (Deletion.deleteProblems report)) && Deletion.deletePlanId report == Nothing) (fail "Checked-out Node was offered a valid deletion plan")
    Deletion.executeDelete executable git directory nodeA "not-a-plan" >>= expectLeft
    _ <- ok git directory ["worktree", "remove", path] ""
    ready <- Deletion.previewDelete git directory nodeA >>= expectRight
    assertEqual [] (Deletion.deleteProblems ready)
    assertTrue "Undeployed Node cannot be deleted" (Deletion.deletePlanId ready /= Nothing)

configuration :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
configuration git executable directory _ = do
    root git directory nodeA
    enable git executable directory
    let key = "branch." ++ BSC.unpack (nodeIdBytes nodeA) ++ ".remote"
    _ <- ok git directory ["config", "--local", "--add", key, "origin"] ""
    plan <- Deletion.previewDelete git directory nodeA >>= expectRight
    assertEqual [BSC.pack key] (Deletion.deleteConfigKeys plan)
    Deletion.executeDelete executable git directory nodeA "bad-confirmation" >>= expectLeft
    _ <- tip git directory nodeA
    original <- maybe (fail "Missing token") pure (Deletion.deletePlanId plan)
    _ <- Deletion.executeDelete executable git directory nodeA original >>= expectRight
    state <- current git directory
    assertEqual Map.empty (managedRefs state)
    exists <- ok git directory ["config", "--local", "--get", "hook.git-roam-reference-transaction.enabled"] ""
    assertEqual "true\n" exists
    values <- runGit git (GitInvocation directory ["config", "--local", "--get-regexp", "^branch\\."] "" []) >>= expectRight
    assertEqual (ExitFailure 1) (gitExitCode values)

stalePlan :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
stalePlan git executable directory _ = do
    root git directory nodeA
    enable git executable directory
    plan <- Deletion.previewDelete git directory nodeA >>= expectRight
    token <- maybe (fail "Missing token") pure (Deletion.deletePlanId plan)
    _ <- makeContent git directory nodeA
    Deletion.executeDelete executable git directory nodeA token >>= expectLeft
    new <- Deletion.previewDelete git directory nodeA >>= expectRight
    assertTrue "Ref changes did not invalidate the confirmation token" (Deletion.deletePlanId new /= Just token)

otherHook :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
otherHook git executable directory _ = do
    root git directory nodeA
    enable git executable directory
    a <- tip git directory nodeA
    _ <- ok git directory ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git directory ["config", "hook.audit.command", "false"] ""
    report <- Deletion.previewDelete git directory nodeA >>= expectRight
    token <- maybe (fail "Missing token") pure (Deletion.deletePlanId report)
    Deletion.executeDelete executable git directory nodeA token >>= expectLeft
    tip git directory nodeA >>= assertEqual a
    _ <- current git directory
    pure ()
