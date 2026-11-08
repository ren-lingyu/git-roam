{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import GitRoam.Application.V2.Inspect
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.V2.History
import GitRoam.Protocol.V2.Repository
import TestSupport
import WorktreeFixture (fixture, nodeA, nodeB, ok, root)

ref :: NodeId -> String
ref node = "refs/heads/" ++ BSC.unpack (nodeIdBytes node)

branchTip :: Git IO -> FilePath -> ObjectFormat -> NodeId -> IO ObjectId
branchTip git directory format node =
    BSC.init <$> ok git directory ["rev-parse", ref node] "" >>= expectRight . parseObjectId format

treeOf :: Git IO -> FilePath -> ObjectId -> IO BS.ByteString
treeOf git directory oid =
    BSC.init <$> ok git directory ["rev-parse", BSC.unpack (objectIdBytes oid) ++ "^{tree}"] ""

commitTree :: Git IO -> FilePath -> BS.ByteString -> [ObjectId] -> String -> ObjectFormat -> IO ObjectId
commitTree git directory content parents message format = do
    bytes <-
        BSC.init
            <$> ok
                git
                directory
                ( ["commit-tree", BSC.unpack content]
                    ++ concatMap (\oid -> ["-p", BSC.unpack (objectIdBytes oid)]) parents
                    ++ ["-m", message]
                )
                ""
    expectRight (parseObjectId format bytes)

setRef :: Git IO -> FilePath -> NodeId -> ObjectId -> IO ()
setRef git directory node oid = do
    _ <- ok git directory ["update-ref", ref node, BSC.unpack (objectIdBytes oid)] ""
    pure ()

inspect :: Git IO -> FilePath -> Maybe NodeId -> IO InspectionReport
inspect git directory selected = inspectState git directory [] selected >>= expectRight

valid :: InspectionReport -> IO ManagedState
valid report = do
    assertEqual [] (reportProblems report)
    expectRight (reportManagedState report)

view :: InspectionReport -> NodeId -> IO NodeView
view report node = case filter ((== node) . viewNode) (reportNodes report) of
    [value] -> pure value
    _ -> fail "Expected exactly one Node view"

main :: IO ()
main =
    runTests $
        [ ("v2 root and local branch identity", fixture "files" Sha1 identity)
        , ("v2 contextual histories with conflicting Roots", fixture "files" Sha1 roots)
        , ("v2 overlap and tree changes reject", fixture "files" Sha1 invalidCheckpoint)
        , ("v2 Node-scoped inspection ignores unrelated invalid branches", fixture "files" Sha1 scope)
        ]
            ++ [ ("v2 independent context inspection " ++ backend ++ " " ++ show format, fixture backend format (contexts format))
               | backend <- ["files", "reftable"]
               , format <- [Sha1, Sha256]
               ]

-- An ordinary UUID branch with a different Node's tip is an invalid managed
-- ref, not an additional Node or an external-context dependency.
identity :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
identity git _ directory _ = do
    root git directory nodeA
    a <- branchTip git directory Sha1 nodeA
    setRef git directory nodeB a
    report <- inspect git directory Nothing
    assertEqual [RefIdentityMismatch nodeB nodeA a] (reportProblems report)

contexts :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
contexts format git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- branchTip git directory format nodeA
    b <- branchTip git directory format nodeB
    aTree <- treeOf git directory a
    bTree <- treeOf git directory b
    bContent <- commitTree git directory bTree [b] "B Content" format
    setRef git directory nodeB bContent

    -- The same external Node may occur more than once in the explicit context.
    k <- commitTree git directory aTree [a, b, bContent] "Selected context" format
    setRef git directory nodeA k
    before <- inspect git directory Nothing >>= valid
    let refs = managedRefs before
    assertEqual (Just k) (Map.lookup nodeA refs)
    node <- inspect git directory Nothing >>= (\r -> view r nodeA)
    assertEqual (Checkpoint a [b, bContent]) (viewKind node)
    assertEqual (Just k) (viewLatestCheckpoint node)
    assertEqual [b, bContent] (viewContextParents node)
    assertEqual 1 (viewCheckpointCount node)

    -- Further Content does not inherit or re-declare a complete context map.
    content <- commitTree git directory aTree [k] "Next Content" format
    setRef git directory nodeA content
    later <- inspect git directory Nothing >>= (\r -> view r nodeA)
    assertEqual (Content k) (viewKind later)
    assertEqual (Just k) (viewLatestCheckpoint later)
    assertEqual [b, bContent] (viewContextParents later)
    assertEqual 1 (viewCheckpointCount later)

    -- A context's old OID remains reachable even after its own branch rewrites.
    setRef git directory nodeB b
    retained <- inspect git directory Nothing >>= valid
    assertEqual (Just b) (Map.lookup nodeB (managedRefs retained))
    -- Ordinary rewriting may abandon old Checkpoints without violating Root.
    candidate <- validateCandidate git directory (Map.insert nodeA a (managedRefs retained)) >>= expectRight
    assertEqual (Right ()) (validateOrdinaryTransition retained candidate)

    -- Deleting the external branch does not invalidate A's recorded context.
    _ <- ok git directory ["update-ref", "-d", ref nodeB] ""
    scoped <- inspect git directory (Just nodeA)
    state <- valid scoped
    assertEqual (Map.singleton nodeA content) (managedRefs state)
    candidateScoped <- validateCandidate git directory (managedRefs state) >>= expectRight
    assertEqual (managedRefs state) (managedRefs candidateScoped)
    absent <- inspectState git directory [] (Just nodeB)
    assertEqual (Left (NodeNotManaged nodeB)) absent

roots :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
roots git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- branchTip git directory Sha1 nodeA
    b <- branchTip git directory Sha1 nodeB
    aTree <- treeOf git directory a
    bTree <- treeOf git directory b
    secondB <- commitTree git directory bTree [] "Competing B Root" Sha1
    unless (b /= secondB) (fail "Fixture created identical Roots")
    k <- commitTree git directory aTree [a, secondB] "Conflicting B context" Sha1
    setRef git directory nodeA k
    outcome <- inspectState git directory [] Nothing
    case outcome of
        Left (HistoryFailure (ConflictingRoots _ _ _)) -> pure ()
        other -> fail ("Expected conflicting Roots: " ++ show other)

invalidCheckpoint :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidCheckpoint git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- branchTip git directory Sha1 nodeA
    b <- branchTip git directory Sha1 nodeB
    aTree <- treeOf git directory a
    aContent <- commitTree git directory aTree [a] "A Content" Sha1
    overlap <- commitTree git directory aTree [a, aContent] "Same-Node context" Sha1
    setRef git directory nodeA overlap
    result <- inspectState git directory [] Nothing
    case result of
        Left (HistoryFailure (OverlappingContextTree _ _)) -> pure ()
        other -> fail ("Expected context overlap: " ++ show other)

    marker <- BSC.init <$> ok git directory ["hash-object", "-w", "--stdin"] "marker"
    note <- BSC.init <$> ok git directory ["hash-object", "-w", "--stdin"] "new note"
    inner <- BSC.init <$> ok git directory ["mktree"] ("100644 blob " <> marker <> "\t.roam\n100644 blob " <> note <> "\tnote.org\n")
    modified <- BSC.init <$> ok git directory ["mktree"] ("040000 tree " <> inner <> "\t" <> nodeIdBytes nodeA <> "\n")
    bad <- commitTree git directory modified [a, b] "Changes content inside checkpoint" Sha1
    setRef git directory nodeA bad
    other <- inspectState git directory [] Nothing
    case other of
        Left (HistoryFailure (CheckpointTreeMismatch _ _)) -> pure ()
        unexpected -> fail ("Expected unchanged-tree constraint: " ++ show unexpected)

-- A node-scoped inspection traverses all of its external context, but does
-- not validate an unrelated local branch merely because it is in the repo.
scope :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
scope git _ directory _ = do
    root git directory nodeA
    nodeC <- expectRight (parseNodeId "33333333-3333-4333-8333-333333333333")
    empty <- BSC.init <$> ok git directory ["mktree"] ""
    invalid <- commitTree git directory empty [] "Not a Node tree" Sha1
    setRef git directory nodeC invalid
    scoped <- inspect git directory (Just nodeA)
    _ <- valid scoped
    full <- inspectState git directory [] Nothing
    case full of
        Left (HistoryFailure (InvalidNodeTree _ _)) -> pure ()
        other -> fail ("Unrelated malformed Node branch was hidden: " ++ show other)
