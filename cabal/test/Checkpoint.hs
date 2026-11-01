{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Checkpoint
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Cli (CheckpointMessage (..), Command (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import TestSupport
import WorktreeFixture

nodeC :: NodeId
nodeC = either error id (parseNodeId "33333333-3333-4333-8333-333333333333")

none :: DependencyEdits
none = DependencyEdits False [] []

revision :: ObjectId -> String
revision = BSC.unpack . objectIdBytes

tip :: Git IO -> FilePath -> NodeId -> IO BS.ByteString
tip git repo node = BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes node)] ""

commit :: Git IO -> FilePath -> BS.ByteString -> [BS.ByteString] -> IO BS.ByteString
commit git repo tree parents = BSC.init <$> ok git repo (["commit-tree", BSC.unpack tree, "-m", "Fixture"] ++ concatMap (\oid -> ["-p", BSC.unpack oid]) parents) ""

content :: Git IO -> FilePath -> NodeId -> IO BS.ByteString
content git repo node = do
    old <- tip git repo node
    tree <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack old ++ "^{tree}"] ""
    new <- commit git repo tree [old]
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes node), BSC.unpack new, BSC.unpack old] ""
    pure new

setup :: Git IO -> FilePath -> FilePath -> IO ()
setup git executable repo = do
    forM_ [nodeA, nodeB, nodeC] $ \node -> do
        root git repo node
        _ <- content git repo node
        pure ()
    _ <- ok git repo ["config", "user.name", "Fixture"] ""
    _ <- ok git repo ["config", "user.email", "fixture@example.invalid"] ""
    enable git executable repo

record :: Git IO -> FilePath -> FilePath -> NodeId -> DependencyEdits -> IO CheckpointResult
record git executable repo node edits = checkpoint executable git repo (Just node) "A knowledge version\n" edits >>= expectRight

raw :: Git IO -> FilePath -> ObjectId -> IO CommitObject
raw git repo oid = do
    format <- BSC.init <$> ok git repo ["rev-parse", "--show-object-format"] "" >>= expectRight . parseObjectFormat
    loadCommit (nativeHistorySource git repo format []) oid >>= expectRight

main :: IO ()
main =
    runTests $
        [("Checkpoint CLI requires explicit message and parses complete edits", arguments)]
            ++ [("first/repeated Checkpoint structure " ++ backend ++ " " ++ show format, fixture backend format structure) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [("refs/OIDs and graft-independent dependency selection " ++ backend ++ " " ++ show format, fixture backend format referenceInputs) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("complete dependency inheritance, removal, replacement and clearing", fixture "files" Sha1 dependencies)
               , ("Content after Checkpoint supplies its exact tree and history", fixture "files" Sha1 editingTail)
               , ("merged formal history is retained through the next Checkpoint", fixture "files" Sha1 mergedHistory)
               , ("invalid and conflicting dependencies write no objects or refs", fixture "files" Sha1 invalidDependencies)
               , ("Root requires prior Content and protection", fixture "files" Sha1 rootAndProtection)
               , ("empty, invalid UTF-8 and NUL messages are refused", fixture "files" Sha1 invalidMessages)
               , ("index, working, untracked and ignored data remain unchanged", fixture "files" Sha1 dirtyState)
               , ("Checkpoint in a dirty main Node worktree preserves the index", fixture "files" Sha1 dirtyMain)
               , ("CLI infers Node and reads UTF-8 message files/stdin", fixture "files" Sha1 cliMessages)
               , ("no sole-branch inference and missing Node refusal", fixture "files" Sha1 selection)
               , ("expected-old refuses a competing Content update", fixture "files" Sha1 competingContent)
               , ("verify protects dependency branch state", fixture "files" Sha1 competingDependency)
               , ("failure after installation never rolls history back", fixture "files" Sha1 postInstallFailure)
               , ("other named reference Hooks still reject installation", fixture "files" Sha1 otherHook)
               ]

arguments :: IO ()
arguments = do
    assertEqual
        (Right (CreateCheckpoint Nothing (InlineMessage "note") (DependencyEdits True [] ["B"])))
        (parseCommand ["checkpoint", "--depend", "B", "-m", "note", "--clear-dependencies"])
    assertEqual
        (Right (CreateCheckpoint (Just nodeA) (FileMessage "-") none))
        (parseCommand ["checkpoint", "--node", BSC.unpack (nodeIdBytes nodeA), "-F", "-"])
    forM_ [["checkpoint"], ["checkpoint", "-m"], ["checkpoint", "-m", "one", "-F", "file"], ["checkpoint", "-m", "one", "--unknown"], ["checkpoint", "-m", "one", "--node", "bad"]] $ expectLeft . parseCommand

referenceInputs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
referenceInputs git executable repo _ = do
    setup git executable repo
    b <- record git executable repo nodeB none
    let oid = revision (checkpointOid b)
    _ <- ok git repo ["tag", "lightweight", oid] ""
    _ <- ok git repo ["tag", "-a", "annotated", "-m", "Version", oid] ""
    _ <- ok git repo ["tag", "-a", "nested", "-m", "Nested", "annotated"] ""
    -- Both repository grafts and replacement refs must leave knowledge selection
    -- and protocol interpretation unchanged. No advice suppression is installed.
    BS.writeFile (repo </> ".git/info/grafts") (objectIdBytes (checkpointOid b) <> "\n")
    _ <- ok git repo ["replace", oid, revision (checkpointContent b)] ""
    forM_ [oid, take 12 oid, "lightweight", "refs/tags/lightweight", "annotated", "refs/tags/nested", BSC.unpack (nodeIdBytes nodeB), "refs/heads/" ++ BSC.unpack (nodeIdBytes nodeB)] $ \input -> do
        value <- record git executable repo nodeA (DependencyEdits True [] [input])
        assertEqual (Map.singleton nodeB (checkpointOid b)) (checkpointDependencies value)
    count <- ok git repo ["count-objects"] ""
    before <- tip git repo nodeA
    forM_ ["lightweight^0", "lightweight~0", "lightweight^{commit}", "lightweight^{}", "lightweight@{0}", "lightweight:note", "lightweight..HEAD", "lightweight...HEAD", ":/Version", "@{-1}"] $ \input -> do
        checkpoint executable git repo (Just nodeA) "Refuse revision expressions" (DependencyEdits False [] [input]) >>= expectLeft
        tip git repo nodeA >>= assertEqual before
        ok git repo ["count-objects"] "" >>= assertEqual count

structure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
structure git executable repo _ = do
    root git repo nodeA
    start <- tip git repo nodeA
    _ <- content git repo nodeA
    _ <- content git repo nodeA
    lastContent <- content git repo nodeA
    enable git executable repo
    a <- record git executable repo nodeA none
    first <- raw git repo (checkpointOid a)
    assertEqual [start, lastContent] (map objectIdBytes (commitParents first))
    assertEqual Map.empty (checkpointDependencies a)
    oldContent <- raw git repo (checkpointContent a)
    assertEqual (commitTree oldContent) (commitTree first)
    b <- record git executable repo nodeA none
    second <- raw git repo (checkpointOid b)
    bridge <- raw git repo (checkpointContent b)
    assertEqual [checkpointOid a, checkpointContent b] (commitParents second)
    assertEqual [checkpointOid a] (commitParents bridge)
    assertEqual (commitTree first) (commitTree bridge)
    assertTrue "Old second parent was reused" (checkpointContent a /= checkpointContent b)
    forM_ [lastContent, start] $ \ancestor -> do
        _ <- ok git repo ["merge-base", "--is-ancestor", BSC.unpack ancestor, revision (checkpointOid b)] ""
        pure ()
    state <- snapshot git repo
    assertEqual (Just 2) (Set.size <$> Map.lookup nodeA (retainedCheckpoints state))

dependencies :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dependencies git executable repo _ = do
    setup git executable repo
    b <- record git executable repo nodeB none
    c <- record git executable repo nodeC none
    a <- record git executable repo nodeA (DependencyEdits False [] (map (revision . checkpointOid) [b, c]))
    inherited <- record git executable repo nodeA none
    assertEqual (checkpointDependencies a) (checkpointDependencies inherited)
    removed <- record git executable repo nodeA (DependencyEdits False [nodeC] [])
    assertEqual (Map.singleton nodeB (checkpointOid b)) (checkpointDependencies removed)
    _ <- content git repo nodeB
    b2 <- record git executable repo nodeB none
    replaced <- record git executable repo nodeA (DependencyEdits False [] [revision (checkpointOid b2)])
    assertEqual (Map.singleton nodeB (checkpointOid b2)) (checkpointDependencies replaced)
    clearedAdded <- record git executable repo nodeA (DependencyEdits True [] [revision (checkpointOid c)])
    assertEqual (Map.singleton nodeC (checkpointOid c)) (checkpointDependencies clearedAdded)
    cleared <- record git executable repo nodeA (DependencyEdits True [] [])
    assertEqual Map.empty (checkpointDependencies cleared)
    forM_ [a, inherited, removed, replaced, clearedAdded, cleared] $ \value -> do
        object <- raw git repo (checkpointOid value)
        assertEqual (Map.elems (checkpointDependencies value)) (drop 2 (commitParents object))
    state <- snapshot git repo
    assertTrue "Historical dependency was discarded" (maybe False (Set.member (checkpointOid b)) (Map.lookup nodeB (retainedCheckpoints state)))

editingTail :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
editingTail git executable repo _ = do
    setup git executable repo
    a <- record git executable repo nodeA none
    w1 <- content git repo nodeA
    w2 <- content git repo nodeA
    next <- record git executable repo nodeA none
    object <- raw git repo (checkpointOid next)
    assertEqual [objectIdBytes (checkpointOid a), w2] (map objectIdBytes (commitParents object))
    _ <- ok git repo ["merge-base", "--is-ancestor", BSC.unpack w1, revision (checkpointOid next)] ""
    pure ()

mergedHistory :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
mergedHistory git executable repo _ = do
    setup git executable repo
    a <- record git executable repo nodeA none
    first <- raw git repo (checkpointOid a)
    rootOid <- case commitParents first of r : _ -> pure (objectIdBytes r); _ -> fail "No Root"
    w2 <- commit git repo (objectIdBytes (commitTree first)) [rootOid]
    k2 <- commit git repo (objectIdBytes (commitTree first)) [rootOid, w2]
    wm <- commit git repo (objectIdBytes (commitTree first)) [objectIdBytes (checkpointOid a)]
    km <- commit git repo (objectIdBytes (commitTree first)) [objectIdBytes (checkpointOid a), wm, k2]
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack km, revision (checkpointOid a)] ""
    next <- record git executable repo nodeA none
    state <- snapshot git repo
    assertEqual (Just 4) (Set.size <$> Map.lookup nodeA (retainedCheckpoints state))
    object <- raw git repo (checkpointOid next)
    assertEqual [km, objectIdBytes (checkpointContent next)] (map objectIdBytes (commitParents object))

invalidDependencies :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidDependencies git executable repo _ = do
    setup git executable repo
    b <- record git executable repo nodeB none
    a <- record git executable repo nodeA (DependencyEdits False [] [revision (checkpointOid b)])
    before <- tip git repo nodeA
    bObject <- raw git repo (checkpointOid b)
    rootOid <- case commitParents bObject of r : _ -> pure r; _ -> fail "Missing Root"
    otherW <- commit git repo (objectIdBytes (commitTree bObject)) [objectIdBytes rootOid]
    otherK <- commit git repo (objectIdBytes (commitTree bObject)) [objectIdBytes rootOid, otherW]
    _ <- content git repo nodeB
    count <- ok git repo ["count-objects"] ""
    let bad =
            [ DependencyEdits False [] [revision rootOid]
            , DependencyEdits False [] [revision (checkpointContent b)]
            , DependencyEdits False [] [revision (checkpointOid a)]
            , DependencyEdits False [] [BSC.unpack otherK]
            , DependencyEdits False [] [BSC.unpack (nodeIdBytes nodeB)]
            , DependencyEdits False [] ["--help"]
            , DependencyEdits False [] [revision (checkpointOid b), revision (checkpointOid b)]
            , DependencyEdits False [nodeB, nodeB] []
            , DependencyEdits False [nodeC] []
            , DependencyEdits False [nodeB] [revision (checkpointOid b)]
            , DependencyEdits True [nodeB] []
            ]
    forM_ bad $ \edits -> do
        checkpoint executable git repo (Just nodeA) "note" edits >>= expectLeft
        tip git repo nodeA >>= assertEqual before
        ok git repo ["count-objects"] "" >>= assertEqual count
    -- A user default suppressing ambiguity warnings must not silently select a
    -- branch/tag dependency. Full refs and explicit OIDs remain available.
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/tags/" <> nodeIdBytes nodeB), revision (checkpointOid b)] ""
    _ <- ok git repo ["config", "core.warnAmbiguousRefs", "false"] ""
    checkpoint executable git repo (Just nodeA) "note" (DependencyEdits False [] [BSC.unpack (nodeIdBytes nodeB)]) >>= expectLeft

rootAndProtection :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
rootAndProtection git executable repo _ = do
    root git repo nodeA
    checkpoint executable git repo (Just nodeA) "note" none >>= expectLeft
    enable git executable repo
    count <- ok git repo ["count-objects"] ""
    checkpoint executable git repo (Just nodeA) "note" none >>= expectLeft
    ok git repo ["count-objects"] "" >>= assertEqual count

invalidMessages :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
invalidMessages git executable repo _ = do
    setup git executable repo
    count <- ok git repo ["count-objects"] ""
    forM_ ["", " \t\n", BS.pack [255], "text\0"] $ \message -> do
        checkpoint executable git repo (Just nodeA) message none >>= expectLeft
        ok git repo ["count-objects"] "" >>= assertEqual count

dirtyState :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyState = dirtyStateAt False

dirtyMain :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyMain = dirtyStateAt True

dirtyStateAt :: Bool -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyStateAt mainCheckout git executable repo parent = do
    setup git executable repo
    let target = if mainCheckout then repo else parent </> "node"
        note = BSC.unpack (nodeIdBytes nodeA) </> "note.org"
    if mainCheckout
        then do
            _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
            pure ()
        else manual git repo target nodeA
    writeFile (target </> note) "committed\n"
    _ <- ok git target ["add", "--", note] ""
    _ <- ok git target ["commit", "-m", "Content"] ""
    committed <- tip git repo nodeA
    writeFile (target </> note) "staged\n"
    _ <- ok git target ["add", "--", note] ""
    writeFile (target </> note) "unstaged\n"
    writeFile (target </> "untracked") "keep"
    writeFile (parent </> "excludes") "ignored\n"
    _ <- ok git repo ["config", "core.excludesFile", parent </> "excludes"] ""
    writeFile (target </> "ignored") "keep ignored"
    before <- ok git target ["status", "--porcelain=v1", "-z", "--ignored=matching"] ""
    indexPath <- BSC.init <$> ok git target ["rev-parse", "--path-format=absolute", "--git-path", "index"] ""
    index <- BS.readFile (BSC.unpack indexPath)
    result <- record git executable repo nodeA none
    afterIndex <- BS.readFile (BSC.unpack indexPath)
    assertEqual index afterIndex
    after <- ok git target ["status", "--porcelain=v1", "-z", "--ignored=matching"] ""
    assertEqual before after
    readFile (target </> note) >>= assertEqual "unstaged\n"
    readFile (target </> "untracked") >>= assertEqual "keep"
    readFile (target </> "ignored") >>= assertEqual "keep ignored"
    tree <- ok git repo ["rev-parse", BSC.unpack committed ++ "^{tree}"] ""
    object <- raw git repo (checkpointOid result)
    assertEqual (BSC.init tree) (objectIdBytes (commitTree object))

cli :: FilePath -> FilePath -> [String] -> BS.ByteString -> IO GitResult
cli executable directory args input = do
    inherited <- getEnvironment
    let env = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
    runGit (nativeGit executable) (GitInvocation directory args input env) >>= expectRight

cliMessages :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliMessages git executable repo parent = do
    setup git executable repo
    _ <- ok git repo ["config", "i18n.commitEncoding", "ISO-8859-1"] ""
    _ <- ok git repo ["config", "i18n.logOutputEncoding", "UTF-8"] ""
    let target = parent </> "node"
        file = parent </> "message\n.txt"
        message = Encoding.encodeUtf8 "确认一个正式知识版本\n\n保留完整依赖.\n"
    manual git repo target nodeA
    BS.writeFile file message
    first <- cli executable (target </> BSC.unpack (nodeIdBytes nodeA)) ["checkpoint", "-F", file] ""
    assertEqual ExitSuccess (gitExitCode first)
    tipA <- tip git repo nodeA
    saved <- ok git repo ["show", "-s", "--format=%B", BSC.unpack tipA] ""
    assertTrue "UTF-8 message changed" (message `BS.isPrefixOf` saved)
    ok git repo ["config", "--get", "i18n.commitEncoding"] "" >>= assertEqual "ISO-8859-1\n"
    repeated <- cli executable target ["checkpoint", "-F", "-"] "Another note\n"
    assertEqual ExitSuccess (gitExitCode repeated)
    missing <- cli executable target ["checkpoint", "-F", parent </> "absent"] ""
    assertTrue "Missing file silently accepted" (gitExitCode missing /= ExitSuccess)
    checked <- cli executable target ["check"] ""
    assertEqual ExitSuccess (gitExitCode checked)
    doesFileExist file >>= assertEqual True

selection :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
selection git executable repo _ = do
    root git repo nodeA
    _ <- content git repo nodeA
    enable git executable repo
    checkpoint executable git repo Nothing "note" none >>= expectLeft
    checkpoint executable git repo (Just nodeC) "note" none >>= expectLeft

isTransaction :: GitInvocation -> Bool
isTransaction invocation = "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation

competingContent :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingContent git executable repo _ = do
    setup git executable repo
    old <- tip git repo nodeA
    tree <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack old ++ "^{tree}"] ""
    edited <- commit git repo tree [old]
    let racing = Git $ \invocation -> do
            if isTransaction invocation
                then do
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack edited, BSC.unpack old]) ""
                    runGit git invocation
                else runGit git invocation
    checkpoint executable racing repo (Just nodeA) "note" none >>= expectLeft
    tip git repo nodeA >>= assertEqual edited

competingDependency :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingDependency git executable repo _ = do
    setup git executable repo
    b <- record git executable repo nodeB none
    oldA <- tip git repo nodeA
    tree <- raw git repo (checkpointOid b)
    edited <- commit git repo (objectIdBytes (commitTree tree)) [objectIdBytes (checkpointOid b)]
    let racing = Git $ \invocation -> do
            if isTransaction invocation
                then do
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), BSC.unpack edited, revision (checkpointOid b)]) ""
                    runGit git invocation
                else runGit git invocation
    checkpoint executable racing repo (Just nodeA) "note" (DependencyEdits False [] [revision (checkpointOid b)]) >>= expectLeft
    tip git repo nodeA >>= assertEqual oldA
    tip git repo nodeB >>= assertEqual edited

postInstallFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
postInstallFailure git executable repo _ = do
    setup git executable repo
    updated <- newIORef False
    let failing = Git $ \invocation -> do
            installed <- atomicModifyIORef' updated (\value -> (value, value))
            if installed && "for-each-ref" `elem` gitArguments invocation
                then pure (Right (GitResult (ExitFailure 1) "" "fixture post-install read failure"))
                else do
                    result <- runGit git invocation
                    if isTransaction invocation
                        then do
                            _ <- atomicModifyIORef' updated (const (True, ()))
                            pure result
                        else pure result
    outcome <- checkpoint executable failing repo (Just nodeA) "note" none
    case outcome of
        Left (CheckpointFailure _ details) -> assertTrue "Installed history was not diagnosed" (any (isPrefixOf "Ref update completed") details)
        Right value -> fail (show value)
    state <- snapshot git repo
    assertEqual (Just 1) (Set.size <$> Map.lookup nodeA (retainedCheckpoints state))

otherHook :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
otherHook git executable repo _ = do
    setup git executable repo
    old <- tip git repo nodeA
    _ <- ok git repo ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git repo ["config", "hook.audit.command", "false"] ""
    checkpoint executable git repo (Just nodeA) "note" none >>= expectLeft
    tip git repo nodeA >>= assertEqual old
