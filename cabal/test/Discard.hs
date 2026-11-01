{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (bracket)
import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Discard
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import GitRoam.Cli (Command (..), HelpTopic (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Discard
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (createDirectory, doesDirectoryExist, doesFileExist, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import System.IO (BufferMode (NoBuffering), hClose, hFlush, hGetChar, hPutStrLn, hSetBuffering)
import System.Posix.IO (fdToHandle)
import System.Posix.Terminal (openPseudoTerminal)
import System.Process (CreateProcess (..), StdStream (..), proc, waitForProcess, withCreateProcess)
import System.Timeout (timeout)
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
            ++ [("confirmed discard and original-path restoration " ++ backend ++ " " ++ show format, fixture backend format execution) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("cross-Node discard commits the exact full closure", fixture "files" Sha1 executeDependencies)
               , ("stale reference plans refuse before mutation", fixture "files" Sha1 stalePlan)
               , ("dirty worktrees invalidate prior confirmation", fixture "files" Sha1 staleDirty)
               , ("execution requires matching enabled protection", fixture "files" Sha1 disabledExecution)
               , ("moved worktrees invalidate prior confirmation", fixture "files" Sha1 staleMoved)
               , ("transaction failure restores old deployment only", fixture "files" Sha1 rejectedTransaction)
               , ("partial removal failure restores confirmed old worktrees", fixture "files" Sha1 partialRemoval)
               , ("other named Hooks can reject discard", fixture "files" Sha1 otherHook)
               , ("failed restoration preserves user data and committed refs", fixture "files" Sha1 failedRestoration)
               , ("lost transaction response never rolls discarded history back", fixture "files" Sha1 lostTransaction)
               , ("dependency verify rejects a competing ref update", fixture "files" Sha1 verifyRace)
               , ("private worktree configuration blocks recreation", fixture "files" Sha1 privateConfig)
               , ("private worktree refs block recreation", fixture "files" Sha1 privateRefs)
               , ("nested affected worktrees require prior undeployment", fixture "files" Sha1 nestedExecution)
               , ("noninteractive execution requires complete plan confirmation", fixture "files" Sha1 cliExecution)
               , ("interactive confirmation executes the displayed plan", fixture "files" Sha1 (interactive True))
               , ("interactive refusal leaves history and deployment unchanged", fixture "files" Sha1 (interactive False))
               ]

arguments :: IO ()
arguments = do
    assertEqual (Right (PreviewDiscard ["A", "B"])) (parseCommand ["discard", "A", "--dry-run", "B"])
    forM_ [["help", "discard"], ["discard", "--help"], ["discard", "-h"]] $ assertEqual (Right (ShowHelp DiscardHelp)) . parseCommand
    assertEqual (Right (ExecuteDiscard ["A"] Nothing)) (parseCommand ["discard", "A"])
    forM_ [["discard"], ["discard", "--dry-run"], ["discard", "--dry-run", "A", "--force"], ["discard", "--dry-run", "A", "--dry-run"], ["discard", "--dry-run", "A", "--confirm", "id"]] $ expectLeft . parseCommand

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

identifier :: DiscardPreview -> IO BS.ByteString
identifier report = do
    assertEqual [] (previewProblems report)
    maybe (fail "No plan identifier") pure (previewPlanId report)

payloadVersion :: Git IO -> FilePath -> NodeId -> ObjectId -> BS.ByteString -> IO ObjectId
payloadVersion git repo node base text = do
    let object bytes = expectRight (parseObjectId (if BS.length bytes == 40 then Sha1 else Sha256) bytes)
    marker <- BSC.init <$> ok git repo ["hash-object", "-w", "--stdin"] ""
    blob <- BSC.init <$> ok git repo ["hash-object", "-w", "--stdin"] text
    inner <- BSC.init <$> ok git repo ["mktree"] ("100644 blob " <> marker <> "\t.roam\n100644 blob " <> blob <> "\tnote.org\n")
    tree <- (BSC.init <$> ok git repo ["mktree"] ("040000 tree " <> inner <> "\t" <> nodeIdBytes node <> "\n")) >>= object
    w <- commit git repo tree [base] (text <> " editing")
    commit git repo tree [base, w] text

executionSetup :: Git IO -> FilePath -> FilePath -> FilePath -> IO (ObjectId, ObjectId, ObjectId, FilePath)
executionSetup git executable repo parent = do
    r <- newRoot git repo nodeA
    k0 <- payloadVersion git repo nodeA r "keep\n"
    k1 <- payloadVersion git repo nodeA k0 "discard\n"
    putTip git repo nodeA k1
    let path = parent </> "node"
    manual git repo path nodeA
    _ <- ok git repo ["config", "user.name", "Fixture"] ""
    _ <- ok git repo ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable repo
    pure (r, k0, k1, path)

execution :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
execution git executable repo parent = do
    (r, k0, k1, original) <- executionSetup git executable repo parent
    let path = parent </> "moved\nnode"
        note = path </> BSC.unpack (nodeIdBytes nodeA) </> "note.org"
    _ <- ok git repo ["worktree", "move", original, path] ""
    token <- preview git repo [k1] >>= identifier
    result <- executeDiscard executable git repo [oidText k1] token >>= expectRight
    assertEqual (Set.singleton k1) (resultDiscarded result)
    assertEqual token (resultPlanId result)
    tip git repo nodeA >>= assertEqual k0
    readFile note >>= assertEqual "keep\n"
    _ <- ok git repo ["cat-file", "-e", oidText k1] ""
    check <- snapshot git repo
    assertEqual (Just (Set.singleton k0)) (Map.lookup nodeA (retainedCheckpoints check))
    forM_ (resultWorktrees result) $ \record -> assertEqual (Just k0) (treeHead record)
    requireProtectionFor executable repo >>= expectRight
    next <- preview git repo [k0] >>= identifier
    _ <- executeDiscard executable git repo [oidText k0] next >>= expectRight
    tip git repo nodeA >>= assertEqual r
    doesFileExist note >>= assertEqual False
    doesFileExist (path </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") >>= assertEqual True

executeDependencies :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
executeDependencies git executable repo parent = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    _ <- newRoot git repo nodeC
    (b0, _) <- version git repo rb [] "B0"
    (b1, _) <- version git repo b0 [] "B1"
    (a0, _) <- version git repo ra [b1] "A0 dependent"
    (a1, _) <- version git repo a0 [] "A1 drops dependency"
    putTip git repo nodeA a1
    putTip git repo nodeB b1
    manual git repo (parent </> "A") nodeA
    manual git repo (parent </> "B") nodeB
    enable git executable repo
    token <- preview git repo [b1] >>= identifier
    result <- executeDiscard executable git repo [oidText b1] token >>= expectRight
    assertEqual (Set.fromList [a0, a1, b1]) (resultDiscarded result)
    tip git repo nodeA >>= assertEqual ra
    tip git repo nodeB >>= assertEqual b0
    assertEqual 2 (length (resultWorktrees result))
    _ <- snapshot git repo
    pure ()

stalePlan :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
stalePlan git executable repo parent = do
    (_, k0, k1, path) <- executionSetup git executable repo parent
    old <- preview git repo [k1] >>= identifier
    duplicate <- preview git repo [k1, k1] >>= identifier
    assertEqual old duplicate
    executeDiscard executable git repo [oidText k1] (BSC.replicate 64 '0') >>= expectLeft
    executeDiscard executable git repo [oidText k0] old >>= expectLeft
    tip git repo nodeA >>= assertEqual k1
    doesDirectoryExist path >>= assertEqual True
    newer <- content git repo k1 "new unconfirmed Content"
    putTip git repo nodeA newer
    executeDiscard executable git repo [oidText k1] old >>= expectLeft
    tip git repo nodeA >>= assertEqual newer
    doesDirectoryExist path >>= assertEqual True
    fresh <- preview git repo [k1] >>= identifier
    assertTrue "Reference change did not invalidate the plan ID" (old /= fresh)

staleDirty :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
staleDirty git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    let note = path </> BSC.unpack (nodeIdBytes nodeA) </> "note.org"
    writeFile note "unsaved\n"
    executeDiscard executable git repo [oidText k1] token >>= expectLeft
    readFile note >>= assertEqual "unsaved\n"
    tip git repo nodeA >>= assertEqual k1

disabledExecution :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
disabledExecution git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    _ <- ok git repo ["config", "hook.git-roam-reference-transaction.enabled", "false"] ""
    executeDiscard executable git repo [oidText k1] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k1
    doesDirectoryExist path >>= assertEqual True

staleMoved :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
staleMoved git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    let moved = parent </> "moved"
    _ <- ok git repo ["worktree", "move", path, moved] ""
    executeDiscard executable git repo [oidText k1] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k1
    doesDirectoryExist moved >>= assertEqual True

isTransaction :: GitInvocation -> Bool
isTransaction invocation = "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation

rejectedTransaction :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
rejectedTransaction git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    let failing = Git $ \invocation -> if isTransaction invocation then pure (Right (GitResult (ExitFailure 1) "" "fixture transaction refusal")) else runGit git invocation
    executeDiscard executable failing repo [oidText k1] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k1
    readFile (path </> BSC.unpack (nodeIdBytes nodeA) </> "note.org") >>= assertEqual "discard\n"

otherHook :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
otherHook git executable repo _ = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    enable git executable repo
    _ <- ok git repo ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git repo ["config", "hook.audit.command", "false"] ""
    token <- preview git repo [k] >>= identifier
    executeDiscard executable git repo [oidText k] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k
    ok git repo ["config", "--get", "hook.audit.command"] "" >>= assertEqual "false\n"

failedRestoration :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
failedRestoration git executable repo parent = do
    (_, k0, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    let failing = Git $ \invocation ->
            if "worktree" `elem` gitArguments invocation && "add" `elem` gitArguments invocation
                then do
                    createDirectory path
                    writeFile (path </> "user-data") "keep"
                    pure (Right (GitResult (ExitFailure 1) "" "fixture checkout failure"))
                else runGit git invocation
    outcome <- executeDiscard executable failing repo [oidText k1] token
    case outcome of
        Left (DiscardFailure _ details) -> assertTrue "Committed transaction not reported" (any (isInfixOf "confirmed: True") details)
        Right result -> fail (show result)
    tip git repo nodeA >>= assertEqual k0
    readFile (path </> "user-data") >>= assertEqual "keep"
    _ <- snapshot git repo
    pure ()

lostTransaction :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lostTransaction git executable repo parent = do
    (_, k0, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    let losing = Git $ \invocation -> do
            result <- runGit git invocation
            pure (if isTransaction invocation then Left (GitTransportError "fixture lost transaction response") else result)
    executeDiscard executable losing repo [oidText k1] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k0
    readFile (path </> BSC.unpack (nodeIdBytes nodeA) </> "note.org") >>= assertEqual "keep\n"

verifyRace :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
verifyRace git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    -- Fixture-only controlled setup of another Node, before re-enabling normal
    -- protection. The competing writer explicitly simulates an uncoordinated ref.
    _ <- ok git repo ["config", "hook.git-roam-reference-transaction.enabled", "false"] ""
    rb <- newRoot git repo nodeB
    _ <- ok git repo ["config", "hook.git-roam-reference-transaction.enabled", "true"] ""
    enable git executable repo
    wb <- content git repo rb "Concurrent B Content"
    token <- preview git repo [k1] >>= identifier
    let racing = Git $ \invocation -> do
            if isTransaction invocation
                then do
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), oidText wb, oidText rb]) ""
                    pure ()
                else pure ()
            runGit git invocation
    executeDiscard executable racing repo [oidText k1] token >>= expectLeft
    tip git repo nodeA >>= assertEqual k1
    tip git repo nodeB >>= assertEqual wb
    doesDirectoryExist path >>= assertEqual False

partialRemoval :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
partialRemoval git executable repo parent = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (a, _) <- version git repo ra [b] "A depends on B"
    putTip git repo nodeA a
    putTip git repo nodeB b
    let pa = parent </> "A"
        pb = parent </> "B"
    manual git repo pa nodeA
    manual git repo pb nodeB
    enable git executable repo
    before <- snapshot git repo
    token <- preview git repo [b] >>= identifier
    count <- newIORef (0 :: Int)
    let failing = Git $ \invocation -> do
            number <- if "worktree" `elem` gitArguments invocation && "remove" `elem` gitArguments invocation then atomicModifyIORef' count (\n -> (n + 1, n + 1)) else pure 0
            if number == 2 then pure (Right (GitResult (ExitFailure 1) "" "fixture second removal failure")) else runGit git invocation
    executeDiscard executable failing repo [oidText b] token >>= expectLeft
    snapshot git repo >>= assertEqual before
    mapM_ (\path -> doesDirectoryExist path >>= assertEqual True) [pa, pb]

privateConfig :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
privateConfig git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    _ <- ok git repo ["config", "extensions.worktreeConfig", "true"] ""
    _ <- ok git path ["config", "--worktree", "user.note", "private"] ""
    report <- preview git repo [k1]
    assertEqual Nothing (previewPlanId report)
    assertTrue "Private configuration omitted" (any (isInfixOf "private configuration") (previewProblems report))

privateRefs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
privateRefs git executable repo parent = do
    (_, _, k1, path) <- executionSetup git executable repo parent
    _ <- ok git path ["update-ref", "refs/worktree/private", oidText k1] ""
    report <- preview git repo [k1]
    assertEqual Nothing (previewPlanId report)
    assertTrue "Private refs omitted" (any (isInfixOf "private refs") (previewProblems report))

nestedExecution :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nestedExecution git executable repo parent = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (a, _) <- version git repo ra [b] "A depends on B"
    putTip git repo nodeA a
    putTip git repo nodeB b
    let path = parent </> "outer"
    writeFile (repo </> ".git/info/exclude") "child/\n"
    manual git repo path nodeA
    manual git repo (path </> "child") nodeB
    enable git executable repo
    report <- preview git repo [b]
    assertEqual Nothing (previewPlanId report)
    assertTrue "Nested target layout not diagnosed" (any (isInfixOf "nested worktree") (previewProblems report))

cliEnvironment :: IO [(String, Maybe String)]
cliEnvironment = do
    inherited <- getEnvironment
    pure ([(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")])

cliExecution :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliExecution git executable repo parent = do
    (_, k0, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    environment <- cliEnvironment
    let call args location = runGit (nativeGit executable) (GitInvocation location args "" environment) >>= expectRight
    refused <- call ["discard", oidText k1] repo
    assertEqual (ExitFailure 1) (gitExitCode refused)
    tip git repo nodeA >>= assertEqual k1
    result <- call ["discard", "--confirm", BSC.unpack token, oidText k1] (path </> BSC.unpack (nodeIdBytes nodeA))
    assertEqual ExitSuccess (gitExitCode result)
    assertTrue "No successful discard diagnostic" ("Discarded 1 Checkpoints" `BS.isInfixOf` gitStdout result)
    tip git repo nodeA >>= assertEqual k0

interactive :: Bool -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
interactive accept git executable repo parent = do
    (_, k0, k1, path) <- executionSetup git executable repo parent
    token <- preview git repo [k1] >>= identifier
    environment <- cliEnvironment
    -- A real PTY exercises the terminal guard, full preview, prompt and reply.
    bracket (openPseudoTerminal >>= \(a, b) -> (,) <$> fdToHandle a <*> fdToHandle b) (\(a, b) -> hClose a >> hClose b) $ \(master, slave) -> do
        hSetBuffering master NoBuffering
        hSetBuffering slave NoBuffering
        inherited <- getEnvironment
        let apply values (key, value) = (maybe id (\text -> ((key, text) :)) value) (filter ((/= key) . fst) values)
            command = (proc executable ["discard", oidText k1]){cwd = Just repo, env = Just (foldl apply inherited environment), std_in = UseHandle slave, std_err = UseHandle slave, std_out = CreatePipe}
            prompt = "Type this plan ID to discard: "
            readPrompt text = if prompt `isInfixOf` text then pure text else if length text > 30000 then fail "Oversized interactive preview" else hGetChar master >>= \c -> readPrompt (text ++ [c])
        withCreateProcess command $ \_ output _ process -> do
            observed <- timeout (10 * 1000000) (readPrompt "") >>= maybe (fail "Interactive prompt timed out") pure
            assertTrue "Interactive preview omitted the plan ID" (BSC.unpack token `isInfixOf` observed)
            assertTrue "Interactive preview omitted worktree recreation" ("fresh Git administration" `isInfixOf` observed)
            hPutStrLn master (if accept then BSC.unpack token else "decline")
            hFlush master
            bytes <- maybe (fail "Missing CLI stdout") BS.hGetContents output
            code <- waitForProcess process
            assertEqual (if accept then ExitSuccess else ExitFailure 1) code
            whenAccepted bytes
    tip git repo nodeA >>= assertEqual (if accept then k0 else k1)
    doesDirectoryExist path >>= assertEqual True
  where
    whenAccepted bytes = if accept then assertTrue "Interactive discard did not finish" ("Discarded 1 Checkpoints" `BS.isInfixOf` bytes) else pure ()
