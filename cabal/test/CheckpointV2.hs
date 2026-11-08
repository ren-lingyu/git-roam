{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import GitRoam.Application.Protection (ownHookBypass)
import qualified GitRoam.Application.V2.Checkpoint as V2
import qualified GitRoam.Application.V2.Inspect as Inspection
import GitRoam.Git
import GitRoam.Git.Objects (nativeHistorySource)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (CommitObject (..), loadCommit)
import GitRoam.Protocol.V2.Repository
import System.Directory (createDirectory)
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture (enable, fixture, manual, nodeA, nodeB, ok, root)

ref :: NodeId -> String
ref node = "refs/heads/" ++ BSC.unpack (nodeIdBytes node)

textOid :: ObjectId -> String
textOid = BSC.unpack . objectIdBytes

tip :: Git IO -> FilePath -> ObjectFormat -> NodeId -> IO ObjectId
tip git directory format node =
    BSC.init <$> ok git directory ["rev-parse", ref node] "" >>= expectRight . parseObjectId format

treeOf :: Git IO -> FilePath -> ObjectId -> IO BS.ByteString
treeOf git directory oid =
    BSC.init <$> ok git directory ["rev-parse", textOid oid ++ "^{tree}"] ""

makeCommit :: Git IO -> FilePath -> ObjectFormat -> BS.ByteString -> [ObjectId] -> String -> IO ObjectId
makeCommit git directory format tree parents message = do
    bytes <- BSC.init <$> ok git directory (["commit-tree", BSC.unpack tree] ++ concatMap (\oid -> ["-p", textOid oid]) parents ++ ["-m", message]) ""
    expectRight (parseObjectId format bytes)

inspect :: Git IO -> FilePath -> IO ManagedState
inspect git directory = do
    report <- Inspection.inspectState git directory [] Nothing >>= expectRight
    assertEqual [] (Inspection.reportProblems report)
    expectRight (Inspection.reportManagedState report)

record :: Git IO -> FilePath -> FilePath -> NodeId -> BS.ByteString -> [ObjectId] -> IO V2.CheckpointResult
record git executable directory node message contexts =
    V2.checkpoint executable git directory node message (map textOid contexts) >>= expectRight

setup :: Git IO -> FilePath -> FilePath -> IO ()
setup git executable directory = do
    root git directory nodeA
    root git directory nodeB
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory

raw :: Git IO -> FilePath -> ObjectFormat -> ObjectId -> IO CommitObject
raw git directory format oid =
    loadCommit (nativeHistorySource git directory format []) oid >>= expectRight

main :: IO ()
main =
    runTests $
        [ ("v2 context validation rejects bad requests before construction", fixture "files" Sha1 invalid)
        , ("v2 recorded context may be an unretained Content commit", fixture "files" Sha1 orphan)
        , ("v2 Checkpoint preserves dirty linked worktree data", fixture "files" Sha1 dirty)
        , ("v2 other named reference Hooks can refuse installation", fixture "files" Sha1 otherHook)
        ]
            ++ [ ("v2 native Checkpoint construction " ++ backend ++ " " ++ show format, fixture backend format (structure format))
               | backend <- ["files", "reftable"]
               , format <- [Sha1, Sha256]
               ]

-- Root is a valid immediate first parent; no prerequisite Content or bridge
-- commit is needed. Two versions of B may be chosen independently in order.
structure :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
structure format git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory format nodeA
    b <- tip git directory format nodeB
    bTree <- treeOf git directory b
    bContent <- makeCommit git directory format bTree [b] "B Content"
    _ <- ok git directory ["update-ref", ref nodeB, textOid bContent] ""
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    _ <- ok git directory ["tag", "-a", "previous-b", "-m", "old B", textOid b] ""
    enable git executable directory

    first <- V2.checkpoint executable git directory nodeA "A records two B versions" ["refs/tags/previous-b", textOid bContent] >>= expectRight
    assertEqual nodeA (V2.checkpointNode first)
    assertEqual a (V2.checkpointPredecessor first)
    assertEqual [b, bContent] (V2.checkpointContexts first)
    firstRaw <- raw git directory format (V2.checkpointOid first)
    assertEqual [a, b, bContent] (commitParents firstRaw)
    aTree <- treeOf git directory a
    assertEqual aTree (objectIdBytes (commitTree firstRaw))

    second <- record git executable directory nodeA "A fixes only the old B Root" [b]
    assertEqual (V2.checkpointOid first) (V2.checkpointPredecessor second)
    secondRaw <- raw git directory format (V2.checkpointOid second)
    assertEqual [V2.checkpointOid first, b] (commitParents secondRaw)
    assertEqual (commitTree firstRaw) (commitTree secondRaw)
    state <- inspect git directory
    assertEqual (Just (V2.checkpointOid second)) (Map.lookup nodeA (managedRefs state))
    view <- Inspection.inspectState git directory [] (Just nodeA) >>= expectRight
    case Inspection.reportNodes view of
        [node] -> do
            assertEqual (Just (V2.checkpointOid second)) (Inspection.viewLatestCheckpoint node)
            assertEqual [b] (Inspection.viewContextParents node)
            assertEqual 2 (Inspection.viewCheckpointCount node)
        _ -> fail "Expected exactly one Node view"

    -- The historical B Content stays reachable from A's first Checkpoint even
    -- when B's own branch moves backwards or is removed.
    _ <- ok git directory (ownHookBypass ++ ["update-ref", ref nodeB, textOid b, textOid bContent]) ""
    _ <- inspect git directory
    _ <- ok git directory (ownHookBypass ++ ["update-ref", "-d", ref nodeB, textOid b]) ""
    remaining <- inspect git directory
    assertEqual (Map.singleton nodeA (V2.checkpointOid second)) (managedRefs remaining)

invalid :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalid git executable directory _ = do
    setup git executable directory
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    otherRoot <- makeCommit git directory Sha1 bTree [] "Another B Root"
    let reject contexts = do
            V2.checkpoint executable git directory nodeA "Do not install" contexts >>= expectLeft
            tip git directory Sha1 nodeA >>= assertEqual a
    forM_
        [ []
        , [textOid b, textOid b]
        , [textOid a]
        , [textOid otherRoot]
        , [textOid b ++ "^0"]
        , ["missing-reference"]
        ]
        reject
    forM_ ["", " \n ", "bad\0message", BS.singleton 255] $ \message -> do
        V2.checkpoint executable git directory nodeA message [textOid b] >>= expectLeft
        tip git directory Sha1 nodeA >>= assertEqual a

orphan :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
orphan git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    unreferenced <- makeCommit git directory Sha1 bTree [b] "Unreferenced B Content"
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory
    value <- record git executable directory nodeA "A references unretained B" [unreferenced]
    assertEqual [unreferenced] (V2.checkpointContexts value)
    state <- inspect git directory
    assertEqual (Just b) (Map.lookup nodeB (managedRefs state))
    _ <- ok git directory (ownHookBypass ++ ["update-ref", "-d", ref nodeB, textOid b]) ""
    _ <- inspect git directory
    pure ()

dirty :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirty git executable directory parent = do
    setup git executable directory
    b <- tip git directory Sha1 nodeB
    let target = parent </> "editable-node"
        bundle = target </> BSC.unpack (nodeIdBytes nodeA)
        note = bundle </> "uncommitted.org"
    manual git directory target nodeA
    createDirectory (bundle </> "empty-untracked")
    writeFile note "* staged but not committed\n"
    _ <- ok git target ["add", "--", BSC.unpack (nodeIdBytes nodeA) ++ "/uncommitted.org"] ""
    before <- ok git target ["ls-files", "--stage", "-z"] ""
    value <- record git executable target nodeA "A fixes B without writing the index" [b]
    after <- ok git target ["ls-files", "--stage", "-z"] ""
    assertEqual before after
    readFile note >>= assertEqual "* staged but not committed\n"
    newTip <- tip git directory Sha1 nodeA
    assertEqual (V2.checkpointOid value) newTip

otherHook :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
otherHook git executable directory _ = do
    setup git executable directory
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    _ <- ok git directory ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git directory ["config", "hook.audit.command", "false"] ""
    V2.checkpoint executable git directory nodeA "Other Hooks are still active" [textOid b] >>= expectLeft
    tip git directory Sha1 nodeA >>= assertEqual a
