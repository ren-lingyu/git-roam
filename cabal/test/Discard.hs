{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Discard
import GitRoam.Cli (Command (..), HelpTopic (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Discard
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import TestSupport
import WorktreeFixture

nodeC :: NodeId
nodeC = either error id (parseNodeId "33333333-3333-4333-8333-333333333333")

oidText :: ObjectId -> String
oidText = BSC.unpack . objectIdBytes

tip :: Git IO -> FilePath -> NodeId -> IO ObjectId
tip git repo node = do
    bytes <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack ("refs/heads/" <> nodeIdBytes node)] ""
    expectRight (parseObjectId (if BS.length bytes == 40 then Sha1 else Sha256) bytes)

putTip :: Git IO -> FilePath -> NodeId -> ObjectId -> IO ()
putTip git repo node oid = do
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes node), oidText oid] ""
    pure ()

stored :: Git IO -> FilePath -> ObjectId -> IO CommitObject
stored git repo oid = loadCommit (nativeHistorySource git repo (if BS.length (objectIdBytes oid) == 40 then Sha1 else Sha256) []) oid >>= expectRight

commit :: Git IO -> FilePath -> ObjectId -> [ObjectId] -> BS.ByteString -> IO ObjectId
commit git repo tree parents message = do
    bytes <- BSC.init <$> ok git repo (["commit-tree", oidText tree] ++ concatMap (\parent -> ["-p", oidText parent]) parents ++ ["-F", "-"]) message
    expectRight (parseObjectId (if BS.length bytes == 40 then Sha1 else Sha256) bytes)

content :: Git IO -> FilePath -> ObjectId -> BS.ByteString -> IO ObjectId
content git repo parent message = do
    object <- stored git repo parent
    commit git repo (commitTree object) [parent] message

version :: Git IO -> FilePath -> ObjectId -> [ObjectId] -> BS.ByteString -> IO (ObjectId, ObjectId)
version git repo parent extra message = do
    w <- content git repo parent (message <> " content")
    object <- stored git repo w
    k <- commit git repo (commitTree object) (parent : w : extra) message
    pure (k, w)

newRoot :: Git IO -> FilePath -> NodeId -> IO ObjectId
newRoot git repo node = root git repo node >> tip git repo node

preview :: Git IO -> FilePath -> [ObjectId] -> IO DiscardPreview
preview git repo targets = previewDiscard git repo (map oidText targets) >>= expectRight

change :: NodeId -> DiscardImpact -> IO NodeDiscard
change node impact = case filter ((== node) . discardNode) (discardNodes impact) of
    [value] -> pure value
    other -> fail (show other)

main :: IO ()
main =
    runTests $
        [("discard CLI is explicit and dry-run only", arguments)]
            ++ [("linear minimal discard preview " ++ backend ++ " " ++ show format, fixture backend format linear) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("old and transitive dependencies propagate through all retained history", fixture "files" Sha1 dependencies)
               , ("dependencies on a non-first-parent formal branch propagate", fixture "files" Sha1 mergedDependencies)
               , ("multiple remaining formal maxima refuse without enlarging discard", fixture "files" Sha1 multipleMaxima)
               , ("a unique remaining side branch is retained", fixture "files" Sha1 uniqueMaximum)
               , ("Content loss distinguishes retained editing history and unaffected tails", fixture "files" Sha1 contentLoss)
               , ("explicit refs, annotated tags and duplicate targets", fixture "files" Sha1 referenceInputs)
               , ("invalid targets and incomplete initial state refuse", fixture "files" Sha1 invalidState)
               , ("dirty affected worktrees are reported without changing their index", fixture "files" Sha1 dirtyWorktree)
               , ("locked and main worktrees are reported as execution blockers", fixture "files" Sha1 specialWorktrees)
               , ("unrelated dirty worktrees do not block preview", fixture "files" Sha1 unrelatedWorktree)
               , ("dry-run invokes only reads and preserves refs, objects and files", fixture "files" Sha1 readOnly)
               , ("concurrent reference changes invalidate the observation", fixture "files" Sha1 changedRefs)
               , ("CLI reports collateral effects and blocked previews", fixture "files" Sha1 cliPreview)
               ]

arguments :: IO ()
arguments = do
    assertEqual (Right (PreviewDiscard ["A", "B"])) (parseCommand ["discard", "A", "--dry-run", "B"])
    forM_ [["help", "discard"], ["discard", "--help"], ["discard", "-h"]] $ assertEqual (Right (ShowHelp DiscardHelp)) . parseCommand
    forM_ [["discard"], ["discard", "A"], ["discard", "--dry-run"], ["discard", "--dry-run", "A", "--force"], ["discard", "--dry-run", "A", "--dry-run"], ["discard", "--dry-run", "A", "--confirm", "id"]] $ expectLeft . parseCommand

linear :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
linear git _ repo _ = do
    r <- newRoot git repo nodeA
    (k0, _) <- version git repo r [] "K0"
    (k1, _) <- version git repo k0 [] "K1"
    (k2, _) <- version git repo k1 [] "K2"
    putTip git repo nodeA k2
    before <- snapshot git repo
    forM_ [(k2, [k2], k1), (k1, [k1, k2], k0), (k0, [k0, k1, k2], r)] $ \(target, removed, new) -> do
        report <- preview git repo [target]
        assertEqual [] (previewProblems report)
        let impact = previewImpact report
        assertEqual (Set.fromList removed) (discardVersions impact)
        actual <- change nodeA impact
        assertEqual (Just new) (discardNewTip actual)
        assertTrue "Explicit target not identified" (maybe False (Set.member ExplicitTarget) (Map.lookup target (discardReasons impact)))
    report <- preview git repo [k1, k2, k1]
    assertEqual (Set.fromList [k1, k2]) (discardTargets (previewImpact report))
    assertEqual (Set.fromList [k1, k2]) (discardVersions (previewImpact report))
    snapshot git repo >>= assertEqual before

dependencies :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dependencies git _ repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    rc <- newRoot git repo nodeC
    (b0, _) <- version git repo rb [] "B0"
    (b1, _) <- version git repo b0 [] "B1"
    (a0, _) <- version git repo ra [] "A0"
    (a1, _) <- version git repo a0 [b1] "A1 depends on B1"
    (a2, _) <- version git repo a1 [] "A2 drops direct B dependency"
    (c0, _) <- version git repo rc [a1] "C0 depends on old A1"
    forM_ [(nodeA, a2), (nodeB, b1), (nodeC, c0)] $ uncurry (putTip git repo)
    -- Git's optional history overlays must not alter the formal closure.
    BS.writeFile (repo </> ".git/info/grafts") (objectIdBytes a2 <> "\n")
    _ <- ok git repo ["replace", oidText a2, oidText a0] ""
    report <- preview git repo [b1]
    assertEqual [] (previewProblems report)
    let impact = previewImpact report
    assertEqual (Set.fromList [b1, a1, a2, c0]) (discardVersions impact)
    assertTrue "Old direct dependency reason missing" (maybe False (Set.member (DependencySuccessor b1)) (Map.lookup a1 (discardReasons impact)))
    assertTrue "Formal propagation reason missing" (maybe False (Set.member (FormalSuccessor a1)) (Map.lookup a2 (discardReasons impact)))
    a <- change nodeA impact
    b <- change nodeB impact
    c <- change nodeC impact
    assertEqual [Just a0, Just b0, Just rc] (map discardNewTip [a, b, c])

forked :: Git IO -> FilePath -> IO (ObjectId, ObjectId, ObjectId, ObjectId, ObjectId)
forked git repo = do
    r <- newRoot git repo nodeA
    (k0, _) <- version git repo r [] "Base"
    (ka, _) <- version git repo k0 [] "Side A"
    (kb, _) <- version git repo k0 [] "Side B"
    (kc, _) <- version git repo k0 [] "Side C"
    (km, _) <- version git repo ka [kb, kc] "Merge all sides"
    putTip git repo nodeA km
    pure (k0, ka, kb, kc, km)

mergedDependencies :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
mergedDependencies git _ repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (side, _) <- version git repo ra [b] "Dependent side"
    (mainline, _) <- version git repo ra [] "Independent mainline"
    (merged, _) <- version git repo mainline [side] "Formal merge"
    putTip git repo nodeA merged
    putTip git repo nodeB b
    report <- preview git repo [b]
    let impact = previewImpact report
    assertEqual [] (previewProblems report)
    assertEqual (Set.fromList [b, side, merged]) (discardVersions impact)
    actual <- change nodeA impact
    assertEqual (Just mainline) (discardNewTip actual)
    assertTrue "Non-first-parent history reason missing" (maybe False (Set.member (FormalSuccessor side)) (Map.lookup merged (discardReasons impact)))

multipleMaxima :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
multipleMaxima git _ repo _ = do
    (_, ka, kb, kc, km) <- forked git repo
    before <- snapshot git repo
    report <- preview git repo [ka]
    let impact = previewImpact report
    assertEqual (Set.fromList [ka, km]) (discardVersions impact)
    assertEqual Nothing (discardCandidate impact)
    actual <- change nodeA impact
    assertEqual (Set.fromList [kb, kc]) (discardRemainingMaxima actual)
    assertEqual Nothing (discardNewTip actual)
    assertEqual Nothing (discardLostContent actual)
    assertTrue "Unrepresentable history was not diagnosed" (any (isInfixOf "multiple maximal") (previewProblems report))
    snapshot git repo >>= assertEqual before

uniqueMaximum :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
uniqueMaximum git _ repo _ = do
    (k0, ka, kb, kc, km) <- forked git repo
    report <- preview git repo [ka, kb]
    let impact = previewImpact report
    assertEqual [] (previewProblems report)
    assertEqual (Set.fromList [ka, kb, km]) (discardVersions impact)
    actual <- change nodeA impact
    assertEqual (Just kc) (discardNewTip actual)
    target <- maybe (fail "No candidate") pure (discardCandidate impact)
    assertEqual (Just (Set.fromList [k0, kc])) (Map.lookup nodeA (retainedCheckpoints target))

contentLoss :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
contentLoss git _ repo _ = do
    r <- newRoot git repo nodeA
    (k0, w0) <- version git repo r [] "K0"
    (k1, w1) <- version git repo k0 [] "K1"
    tailA <- content git repo k1 "unconfirmed A"
    putTip git repo nodeA tailA
    rb <- newRoot git repo nodeB
    (b0, wb) <- version git repo rb [] "B0"
    tailB <- content git repo b0 "unconfirmed B"
    putTip git repo nodeB tailB
    report <- preview git repo [k1]
    actual <- change nodeA (previewImpact report)
    assertEqual (Just (Set.fromList [w1, tailA])) (discardLostContent actual)
    target <- maybe (fail "No candidate") pure (discardCandidate (previewImpact report))
    assertEqual (Just tailB) (Map.lookup nodeB (managedRefs target))
    assertTrue "Retained Content incorrectly lost" (all (`Set.notMember` maybe Set.empty id (discardLostContent actual)) [w0, wb, tailB])

referenceInputs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
referenceInputs git _ repo _ = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    _ <- ok git repo ["tag", "-a", "version", "-m", "Version", oidText k] ""
    forM_ [["version"], ["refs/tags/version"], [take 12 (oidText k)], [BSC.unpack (nodeIdBytes nodeA)], [oidText k, oidText k]] $ \inputs -> do
        report <- previewDiscard git repo inputs >>= expectRight
        assertEqual (Set.singleton k) (discardTargets (previewImpact report))
    forM_ ["version~0", "version^0", "version@{0}", "version^{commit}"] $ \input -> expectLeft =<< previewDiscard git repo [input]
    _ <- ok git repo ["update-ref", "refs/heads/version", oidText k] ""
    _ <- ok git repo ["config", "core.warnAmbiguousRefs", "false"] ""
    expectLeft =<< previewDiscard git repo ["version"]

invalidState :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidState git _ repo _ = do
    r <- newRoot git repo nodeA
    (k, w) <- version git repo r [] "K"
    (orphan, _) <- version git repo r [] "Unretained K"
    putTip git repo nodeA k
    forM_ [[r], [w], [orphan], []] $ \targets -> expectLeft =<< previewDiscard git repo (map oidText targets)
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (a, _) <- version git repo k [b] "A depends on unretained B"
    putTip git repo nodeA a
    expectLeft =<< previewDiscard git repo [oidText k]

dirtyWorktree :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyWorktree git _ repo parent = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    let path = parent </> "node"
        note = path </> BSC.unpack (nodeIdBytes nodeA) </> "note.org"
    manual git repo path nodeA
    writeFile note "staged\n"
    _ <- ok git path ["add", "--", note] ""
    writeFile note "unstaged\n"
    writeFile (path </> "untracked") "user data\n"
    indexPath <- BSC.init <$> ok git path ["rev-parse", "--path-format=absolute", "--git-path", "index"] ""
    before <- BS.readFile (BSC.unpack indexPath)
    report <- preview git repo [k]
    assertTrue "Dirty worktree was accepted" (not (null (previewProblems report)))
    assertEqual 1 (length (previewWorktrees report))
    BS.readFile (BSC.unpack indexPath) >>= assertEqual before
    readFile note >>= assertEqual "unstaged\n"
    readFile (path </> "untracked") >>= assertEqual "user data\n"

specialWorktrees :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
specialWorktrees git _ repo parent = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    let path = parent </> "node"
    manual git repo path nodeA
    _ <- ok git repo ["worktree", "lock", path] ""
    locked <- preview git repo [k]
    assertTrue "Locked worktree was not reported" (not (null (previewProblems locked)))
    _ <- ok git repo ["worktree", "unlock", path] ""
    _ <- ok git repo ["worktree", "remove", path] ""
    _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
    mainReport <- preview git repo [k]
    assertTrue "Main worktree was not reported" (any (isInfixOf "main worktree") (previewProblems mainReport))
    assertTrue "Main worktree omitted" (any treeMain (previewWorktrees mainReport))

unrelatedWorktree :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
unrelatedWorktree git _ repo parent = do
    ra <- newRoot git repo nodeA
    (a, _) <- version git repo ra [] "A"
    putTip git repo nodeA a
    _ <- newRoot git repo nodeB
    let path = parent </> "unrelated"
    manual git repo path nodeB
    writeFile (path </> "untracked") "unrelated data"
    report <- preview git repo [a]
    assertEqual [] (previewProblems report)
    assertEqual [] (previewWorktrees report)
    readFile (path </> "untracked") >>= assertEqual "unrelated data"

readOnly :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
readOnly git _ repo parent = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    let path = parent </> "node"
    manual git repo path nodeA
    before <- snapshot git repo
    objects <- ok git repo ["count-objects"] ""
    config <- BS.readFile (repo </> ".git/config")
    let observing = Git $ \invocation -> do
            let args = gitArguments invocation
            unless (all (`notElem` args) ["update-ref", "commit-tree", "hash-object", "mktree", "add", "remove", "--local"]) (fail ("Mutation in preview: " ++ show args))
            assertTrue "Deprecated graft override returned" (all ((/= "GIT_GRAFT_FILE") . fst) (gitEnvironment invocation))
            runGit git invocation
    report <- preview observing repo [k]
    assertEqual [] (previewProblems report)
    snapshot git repo >>= assertEqual before
    ok git repo ["count-objects"] "" >>= assertEqual objects
    BS.readFile (repo </> ".git/config") >>= assertEqual config
    -- Ignored data is unsafe even on an otherwise committed tree. The preview
    -- must only report, never remove it.
    writeFile (repo </> ".git/info/exclude") "ignored\n"
    writeFile (path </> "ignored") "keep"
    unsafe <- preview git repo [k]
    assertTrue "Ignored file was accepted" (not (null (previewProblems unsafe)))
    readFile (path </> "ignored") >>= assertEqual "keep"
    removeFile (path </> "ignored")

changedRefs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
changedRefs git _ repo _ = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    w <- content git repo k "Concurrent content"
    refReads <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    count <- atomicModifyIORef' refReads (\n -> (n + 1, n + 1))
                    if count == 4 then putTip git repo nodeA w else pure ()
                else pure ()
            runGit git invocation
    result <- previewDiscard racing repo [oidText k]
    case result of
        Left problem -> assertTrue "Changed observation not diagnosed" ("refs changed" `isInfixOf` problem)
        Right report -> fail (show report)
    tip git repo nodeA >>= assertEqual w

cliPreview :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliPreview git executable repo parent = do
    r <- newRoot git repo nodeA
    (k0, _) <- version git repo r [] "K0"
    (k1, _) <- version git repo k0 [] "K1"
    putTip git repo nodeA k1
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
        invoke = runGit (nativeGit executable) (GitInvocation repo ["discard", "--dry-run", oidText k0] "" environment) >>= expectRight
    output <- invoke
    assertEqual ExitSuccess (gitExitCode output)
    forM_ ["target " <> objectIdBytes k0, "discard " <> objectIdBytes k1, "formal-history successor", " (Root)", "Content commits losing managed entry: 2"] $ \expected -> assertTrue "Incomplete discard preview" (expected `BS.isInfixOf` gitStdout output)
    let path = parent </> "node"
    manual git repo path nodeA
    writeFile (path </> "untracked") "keep"
    blocked <- invoke
    assertEqual (ExitFailure 1) (gitExitCode blocked)
    assertTrue "Blocked preview lost its impact report" (("discard " <> objectIdBytes k1) `BS.isInfixOf` gitStdout blocked)
    assertTrue "No blocker reported" ("blocked " `BS.isInfixOf` gitStdout blocked)
    tip git repo nodeA >>= assertEqual k1
