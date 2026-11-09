{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Checkpoint as Checkpoints
import qualified GitRoam.Application.Inspect as Inspection
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Cli (CheckpointMessage (..), Command (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects (nativeHistorySource)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (CommitObject (..), loadCommit)
import GitRoam.Protocol.Repository
import System.Directory (createDirectory, doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
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

record :: Git IO -> FilePath -> FilePath -> NodeId -> BS.ByteString -> [ObjectId] -> IO Checkpoints.CheckpointResult
record git executable directory node message contexts =
    Checkpoints.checkpoint executable git directory (Just node) message (map textOid contexts) >>= expectRight

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

cli :: FilePath -> FilePath -> [String] -> BS.ByteString -> IO GitResult
cli executable directory argv input = do
    inherited <- getEnvironment
    let environment =
            [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
                ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
    runGit (nativeGit executable) (GitInvocation directory argv input environment) >>= expectRight

isTransaction :: GitInvocation -> Bool
isTransaction invocation = "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation

arguments :: IO ()
arguments = do
    assertEqual
        (Right (CreateCheckpoint Nothing (InlineMessage "note") ["B", "C"]))
        (parseCommand ["checkpoint", "-m", "note", "--context", "B", "--context", "C"])
    assertEqual
        (Right (CreateCheckpoint (Just nodeA) (FileMessage "-") ["B"]))
        (parseCommand ["checkpoint", "--node", BSC.unpack (nodeIdBytes nodeA), "-F", "-", "--context", "B"])
    forM_
        [ ["checkpoint"]
        , ["checkpoint", "-m", "note"]
        , ["checkpoint", "-m", "one", "-F", "file", "--context", "B"]
        , ["checkpoint", "-m", "note", "--context"]
        , ["checkpoint", "-m", "note", "--unknown"]
        ]
        (expectLeft . parseCommand)

main :: IO ()
main =
    runTests $
        [ ("Checkpoint CLI parser requires and preserves explicit contexts", arguments)
        , ("context validation rejects bad requests before construction", fixture "files" Sha1 invalid)
        , ("context revisions accept refs and unambiguous OIDs", fixture "files" Sha1 referenceInputs)
        , ("recorded context may be an unretained Content commit", fixture "files" Sha1 orphan)
        , ("Checkpoint preserves dirty linked worktree data", fixture "files" Sha1 dirty)
        , ("Checkpoint preserves staged, unstaged, untracked and ignored state", fixture "files" Sha1 dirtyState)
        , ("Checkpoint preserves a dirty main Node worktree", fixture "files" Sha1 dirtyMain)
        , ("CLI reads UTF-8 message files and stdin without changing encoding config", fixture "files" Sha1 cliMessages)
        ,
            ( "Node inference refuses ordinary branches and detached HEADs"
            , fixture "files" Sha1 selection
            )
        ,
            ( "CLI infers a Node from the main worktree on a UUID branch"
            , fixture "files" Sha1 mainWorktreeInference
            )
        , ("other named reference Hooks can refuse installation", fixture "files" Sha1 otherHook)
        ,
            ( "CLI infers Node from a linked worktree when --node is omitted"
            , fixture "files" Sha1 inferNodeCli
            )
        , ("CLI warns but accepts multiple contexts from one external Node", fixture "files" Sha1 repeatedNodeWarning)
        , ("competing target-ref updates are refused without overwriting the winner", fixture "files" Sha1 competingRef)
        , ("competing context-ref updates are detected by full-state verification", fixture "files" Sha1 competingContextRef)
        , ("post-install failures report actual state without rollback", fixture "files" Sha1 postInstallFailure)
        ]
            ++ [ ("native Checkpoint construction " ++ backend ++ " " ++ show format, fixture backend format (structure format))
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

    first <- Checkpoints.checkpoint executable git directory (Just nodeA) "A records two B versions" ["refs/tags/previous-b", textOid bContent] >>= expectRight
    assertEqual nodeA (Checkpoints.checkpointNode first)
    assertEqual a (Checkpoints.checkpointPredecessor first)
    assertEqual [b, bContent] (Checkpoints.checkpointContexts first)
    assertEqual 1 (length (Checkpoints.checkpointWarnings first))
    firstRaw <- raw git directory format (Checkpoints.checkpointOid first)
    assertEqual [a, b, bContent] (commitParents firstRaw)
    aTree <- treeOf git directory a
    assertEqual aTree (objectIdBytes (commitTree firstRaw))

    second <- record git executable directory nodeA "A fixes only the old B Root" [b]
    assertEqual [] (Checkpoints.checkpointWarnings second)
    assertEqual (Checkpoints.checkpointOid first) (Checkpoints.checkpointPredecessor second)
    secondRaw <- raw git directory format (Checkpoints.checkpointOid second)
    assertEqual [Checkpoints.checkpointOid first, b] (commitParents secondRaw)
    assertEqual (commitTree firstRaw) (commitTree secondRaw)
    state <- inspect git directory
    assertEqual (Just (Checkpoints.checkpointOid second)) (Map.lookup nodeA (managedRefs state))
    view <- Inspection.inspectState git directory [] (Just nodeA) >>= expectRight
    case Inspection.reportNodes view of
        [node] -> do
            assertEqual (Just (Checkpoints.checkpointOid second)) (Inspection.viewLatestCheckpoint node)
            assertEqual [b] (Inspection.viewContextParents node)
            assertEqual 2 (Inspection.viewCheckpointCount node)
        _ -> fail "Expected exactly one Node view"

    -- The historical B Content stays reachable from A's first Checkpoint even
    -- when B's own branch moves backwards or is removed.
    _ <- ok git directory (ownHookBypass ++ ["update-ref", ref nodeB, textOid b, textOid bContent]) ""
    _ <- inspect git directory
    _ <- ok git directory (ownHookBypass ++ ["update-ref", "-d", ref nodeB, textOid b]) ""
    remaining <- inspect git directory
    assertEqual (Map.singleton nodeA (Checkpoints.checkpointOid second)) (managedRefs remaining)

invalid :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalid git executable directory _ = do
    setup git executable directory
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    otherRoot <- makeCommit git directory Sha1 bTree [] "Another B Root"
    count <- ok git directory ["count-objects"] ""
    let reject contexts = do
            Checkpoints.checkpoint executable git directory (Just nodeA) "Do not install" contexts >>= expectLeft
            tip git directory Sha1 nodeA >>= assertEqual a
            ok git directory ["count-objects"] "" >>= assertEqual count
    forM_
        [ []
        , [textOid b, textOid b]
        , [textOid a]
        , [textOid otherRoot]
        , [textOid b ++ "^0"]
        , [textOid b ++ "~0"]
        , [textOid b ++ "^{commit}"]
        , [textOid b ++ "^{}"]
        , [textOid b ++ "@{0}"]
        , [textOid b ++ ":note"]
        , [textOid b ++ "..HEAD"]
        , [textOid b ++ "...HEAD"]
        , [":/Version"]
        , ["@{-1}"]
        , ["missing-reference"]
        ]
        reject
    forM_ ["", " \n ", "bad\0message", BS.singleton 255] $ \message -> do
        Checkpoints.checkpoint executable git directory (Just nodeA) message [textOid b] >>= expectLeft
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
    assertEqual [unreferenced] (Checkpoints.checkpointContexts value)
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
    assertEqual (Checkpoints.checkpointOid value) newTip

otherHook :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
otherHook git executable directory _ = do
    setup git executable directory
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    _ <- ok git directory ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git directory ["config", "hook.audit.command", "false"] ""
    Checkpoints.checkpoint executable git directory (Just nodeA) "Other Hooks are still active" [textOid b] >>= expectLeft
    tip git directory Sha1 nodeA >>= assertEqual a

referenceInputs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
referenceInputs git executable directory _ = do
    setup git executable directory
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    bContent <- makeCommit git directory Sha1 bTree [b] "B Content"
    _ <- ok git directory ["update-ref", ref nodeB, textOid bContent] ""
    _ <- ok git directory ["tag", "lightweight", textOid bContent] ""
    _ <- ok git directory ["tag", "-a", "annotated", "-m", "Version", textOid bContent] ""
    _ <- ok git directory ["tag", "-a", "nested", "-m", "Nested", "annotated"] ""
    forM_
        [ textOid bContent
        , take 12 (textOid bContent)
        , "lightweight"
        , "refs/tags/lightweight"
        , "annotated"
        , "refs/tags/nested"
        , BSC.unpack (nodeIdBytes nodeB)
        , ref nodeB
        ]
        $ \revision -> do
            -- Each spelling must resolve to the same stored commit.
            resolved <- Checkpoints.checkpoint executable git directory (Just nodeA) "Resolve a reference spelling" [revision] >>= expectRight
            assertEqual [bContent] (Checkpoints.checkpointContexts resolved)

inferNodeCli :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
inferNodeCli git executable directory parent = do
    root git directory nodeA
    root git directory nodeB
    b <- tip git directory Sha1 nodeB
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory
    let worktree = parent </> "inferred-node"
    manual git directory worktree nodeA
    result <- cli executable worktree ["checkpoint", "-m", "Inferred from worktree", "--context", textOid b] ""
    assertEqual ExitSuccess (gitExitCode result)
    assertTrue "Inferred Node UUID missing from output" (nodeIdBytes nodeA `BS.isInfixOf` gitStdout result)
    assertTrue "Unexpected warning for a single external Node context" (BS.null (gitStderr result))
    report <- Inspection.inspectState git directory [] Nothing >>= expectRight
    assertEqual [] (Inspection.reportProblems report)
    assertEqual 2 (length (Inspection.reportNodes report))

dirtyState :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyState = dirtyStateAt False

dirtyMain :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyMain = dirtyStateAt True

dirtyStateAt :: Bool -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyStateAt mainCheckout git executable directory parent = do
    setup git executable directory
    b <- tip git directory Sha1 nodeB
    let target = if mainCheckout then directory else parent </> "dirty-node"
        note = BSC.unpack (nodeIdBytes nodeA) </> "note.org"
    if mainCheckout
        then ok git directory ["switch", BSC.unpack (nodeIdBytes nodeA)] "" >> pure ()
        else manual git directory target nodeA
    writeFile (target </> note) "committed\n"
    _ <- ok git target ["add", "--", note] ""
    _ <- ok git target ["commit", "-m", "Content"] ""
    committed <- tip git directory Sha1 nodeA
    writeFile (target </> note) "staged\n"
    _ <- ok git target ["add", "--", note] ""
    writeFile (target </> note) "unstaged\n"
    writeFile (target </> "untracked") "keep"
    writeFile (parent </> "excludes") "ignored\n"
    _ <- ok git directory ["config", "core.excludesFile", parent </> "excludes"] ""
    writeFile (target </> "ignored") "keep ignored"
    before <- ok git target ["status", "--porcelain=v1", "-z", "--ignored=matching"] ""
    indexPath <- BSC.init <$> ok git target ["rev-parse", "--path-format=absolute", "--git-path", "index"] ""
    index <- BS.readFile (BSC.unpack indexPath)
    result <- record git executable target nodeA "Preserve all local edits" [b]
    afterIndex <- BS.readFile (BSC.unpack indexPath)
    assertEqual index afterIndex
    after <- ok git target ["status", "--porcelain=v1", "-z", "--ignored=matching"] ""
    assertEqual before after
    readFile (target </> note) >>= assertEqual "unstaged\n"
    readFile (target </> "untracked") >>= assertEqual "keep"
    readFile (target </> "ignored") >>= assertEqual "keep ignored"
    tree <- ok git directory ["rev-parse", textOid committed ++ "^{tree}"] ""
    object <- raw git directory Sha1 (Checkpoints.checkpointOid result)
    assertEqual (BSC.init tree) (objectIdBytes (commitTree object))

cliMessages :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliMessages git executable directory parent = do
    setup git executable directory
    _ <- ok git directory ["config", "i18n.commitEncoding", "ISO-8859-1"] ""
    _ <- ok git directory ["config", "i18n.logOutputEncoding", "UTF-8"] ""
    let target = parent </> "message-node"
        bundle = target </> BSC.unpack (nodeIdBytes nodeA)
        file = parent </> "message\n.txt"
        message = Encoding.encodeUtf8 "确认一个 Checkpoint\n\n保留完整上下文.\n"
    b <- tip git directory Sha1 nodeB
    manual git directory target nodeA
    BS.writeFile file message
    first <- cli executable bundle ["checkpoint", "-F", file, "--context", textOid b] ""
    assertEqual ExitSuccess (gitExitCode first)
    tipA <- tip git directory Sha1 nodeA
    saved <- ok git directory ["show", "-s", "--format=%B", textOid tipA] ""
    assertTrue "UTF-8 message changed" (message `BS.isPrefixOf` saved)
    ok git directory ["config", "--get", "i18n.commitEncoding"] "" >>= assertEqual "ISO-8859-1\n"
    repeated <- cli executable bundle ["checkpoint", "-F", "-", "--context", textOid b] "Another note\n"
    assertEqual ExitSuccess (gitExitCode repeated)
    missing <- cli executable bundle ["checkpoint", "-F", parent </> "absent", "--context", textOid b] ""
    assertTrue "Missing message file silently accepted" (gitExitCode missing /= ExitSuccess)
    checked <- cli executable bundle ["check"] ""
    assertEqual ExitSuccess (gitExitCode checked)
    doesFileExist file >>= assertEqual True

selection :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
selection git executable directory parent = do
    setup git executable directory
    b <- tip git directory Sha1 nodeB
    Checkpoints.checkpoint
        executable
        git
        directory
        Nothing
        "Cannot infer from ordinary main branch"
        [textOid b]
        >>= expectLeft
    missing <- expectRight (parseNodeId "33333333-3333-4333-8333-333333333333")
    Checkpoints.checkpoint executable git directory (Just missing) "No managed Node" [textOid b] >>= expectLeft
    let detached = parent </> "detached"
    _ <- ok git directory ["worktree", "add", "--detach", detached, BSC.unpack (nodeIdBytes nodeA)] ""
    Checkpoints.checkpoint executable git detached Nothing "Cannot infer detached HEAD" [textOid b] >>= expectLeft

mainWorktreeInference :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
mainWorktreeInference git executable directory _ = do
    setup git executable directory
    b <- tip git directory Sha1 nodeB
    _ <- ok git directory ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
    headRef <- ok git directory ["symbolic-ref", "-q", "HEAD"] ""
    assertEqual ("refs/heads/" <> nodeIdBytes nodeA <> "\n") headRef
    inferred <- Inspection.inferNode git directory >>= expectRight
    assertEqual (Just nodeA) inferred
    result <-
        cli
            executable
            directory
            ["checkpoint", "-m", "Inferred from main worktree", "--context", textOid b]
            ""
    assertEqual ExitSuccess (gitExitCode result)
    assertTrue
        "Inferred Node UUID missing from output"
        (nodeIdBytes nodeA `BS.isInfixOf` gitStdout result)
    assertTrue "Unexpected warning for a single external Node context" (BS.null (gitStderr result))
    report <- Inspection.inspectState git directory [] Nothing >>= expectRight
    assertEqual [] (Inspection.reportProblems report)
    assertEqual 2 (length (Inspection.reportNodes report))

repeatedNodeWarning :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
repeatedNodeWarning git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    bContent <- makeCommit git directory Sha1 bTree [b] "B Content"
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory
    result <- cli executable directory ["checkpoint", "--node", BSC.unpack (nodeIdBytes nodeA), "-m", "Repeated Node contexts", "--context", textOid b, "--context", textOid bContent] ""
    assertEqual ExitSuccess (gitExitCode result)
    assertTrue "Repeated-Node compatibility warning missing" ("Multiple context commits belong to the same Node" `BS.isInfixOf` gitStderr result)
    rawCommit <- raw git directory Sha1 =<< tip git directory Sha1 nodeA
    assertEqual [a, b, bContent] (commitParents rawCommit)

competingRef :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingRef git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    tree <- treeOf git directory a
    edited <- makeCommit git directory Sha1 tree [a] "Competing Content"
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory
    let racing = Git $ \invocation -> do
            if isTransaction invocation
                then do
                    _ <- ok git directory (ownHookBypass ++ ["update-ref", ref nodeA, textOid edited, textOid a]) ""
                    runGit git invocation
                else runGit git invocation
    Checkpoints.checkpoint executable racing directory (Just nodeA) "Must not overwrite" [textOid b] >>= expectLeft
    tip git directory Sha1 nodeA >>= assertEqual edited

competingContextRef :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingContextRef git executable directory _ = do
    setup git executable directory
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    bTree <- treeOf git directory b
    editedB <- makeCommit git directory Sha1 bTree [b] "Competing B Content"
    let racing = Git $ \invocation -> do
            if isTransaction invocation
                then do
                    _ <- ok git directory (ownHookBypass ++ ["update-ref", ref nodeB, textOid editedB, textOid b]) ""
                    runGit git invocation
                else runGit git invocation
    Checkpoints.checkpoint executable racing directory (Just nodeA) "Context ref raced" [textOid b] >>= expectLeft
    tip git directory Sha1 nodeA >>= assertEqual a
    tip git directory Sha1 nodeB >>= assertEqual editedB

postInstallFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
postInstallFailure git executable directory _ = do
    root git directory nodeA
    root git directory nodeB
    a <- tip git directory Sha1 nodeA
    b <- tip git directory Sha1 nodeB
    _ <- ok git directory ["config", "user.name", "Fixture"] ""
    _ <- ok git directory ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable directory
    updated <- newIORef False
    let failing = Git $ \invocation -> do
            installed <- readIORef updated
            if installed && "for-each-ref" `elem` gitArguments invocation
                then pure (Right (GitResult (ExitFailure 1) "" "fixture post-install read failure"))
                else do
                    result <- runGit git invocation
                    if isTransaction invocation
                        then writeIORef updated True >> pure result
                        else pure result
    outcome <- Checkpoints.checkpoint executable failing directory (Just nodeA) "Installed, then inspection failed" [textOid b]
    case outcome of
        Left (Checkpoints.CheckpointFailure _ details) ->
            assertTrue "Installed history was not diagnosed" (any ("Ref update completed" `isPrefixOf`) details)
        Right value -> fail (show value)
    current <- tip git directory Sha1 nodeA
    assertTrue "Post-install failure rolled the ref back" (current /= a)
