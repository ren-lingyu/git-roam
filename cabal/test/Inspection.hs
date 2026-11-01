{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (atomicModifyIORef', newIORef)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Inspect
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (doesFileExist, findExecutable, makeAbsolute, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport

uuidA, uuidB, uuidC :: BS.ByteString
uuidA = "11111111-1111-4111-8111-111111111111"
uuidB = "22222222-2222-4222-8222-222222222222"
uuidC = "33333333-3333-4333-8333-333333333333"

native :: Git IO
native = nativeGit defaultGitExecutable

fixtureEnvironment :: IO [(String, Maybe String)]
fixtureEnvironment = do
    inherited <- getEnvironment
    pure $
        [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
            ++ [ ("GIT_CONFIG_NOSYSTEM", Just "1")
               , ("GIT_CONFIG_GLOBAL", Just "/dev/null")
               , ("GIT_AUTHOR_NAME", Just "Git Roam Fixture")
               , ("GIT_AUTHOR_EMAIL", Just "fixture@example.invalid")
               , ("GIT_COMMITTER_NAME", Just "Git Roam Fixture")
               , ("GIT_COMMITTER_EMAIL", Just "fixture@example.invalid")
               , ("GIT_AUTHOR_DATE", Just "2000-01-01T00:00:00+0000")
               , ("GIT_COMMITTER_DATE", Just "2000-01-01T00:00:00+0000")
               , ("GIT_TERMINAL_PROMPT", Just "0")
               , ("GIT_ALLOW_PROTOCOL", Just "file")
               ]

invoke :: [(String, Maybe String)] -> FilePath -> [String] -> BS.ByteString -> IO GitResult
invoke environment directory arguments input =
    runGit native (GitInvocation directory arguments input environment) >>= expectRight

ok :: [(String, Maybe String)] -> FilePath -> [String] -> BS.ByteString -> IO BS.ByteString
ok environment directory arguments input = do
    result <- invoke environment directory arguments input
    unless (gitExitCode result == ExitSuccess) (fail (show result))
    pure (gitStdout result)

line :: BS.ByteString -> BS.ByteString
line = BS.takeWhile (/= 10)

nodeId :: BS.ByteString -> NodeId
nodeId = either error id . parseNodeId

objectId :: ObjectFormat -> BS.ByteString -> ObjectId
objectId format = either error id . parseObjectId format . line

makeRoot :: [(String, Maybe String)] -> FilePath -> BS.ByteString -> String -> IO (BS.ByteString, BS.ByteString, BS.ByteString)
makeRoot environment directory uuid message = do
    marker <- line <$> ok environment directory ["hash-object", "-w", "--stdin"] "historical marker is not empty\n"
    contents <- line <$> ok environment directory ["mktree"] ("100644 blob " <> marker <> "\t.roam\n")
    top <- line <$> ok environment directory ["mktree"] ("040000 tree " <> contents <> "\t" <> uuid <> "\n")
    root <- makeCommit environment directory top [] message
    setRef environment directory uuid root
    pure (root, top, marker)

makeCommit :: [(String, Maybe String)] -> FilePath -> BS.ByteString -> [BS.ByteString] -> String -> IO BS.ByteString
makeCommit environment directory content parents message =
    line
        <$> ok
            environment
            directory
            (["commit-tree", BSC.unpack content] ++ concatMap (\oid -> ["-p", BSC.unpack oid]) parents ++ ["-m", message])
            BS.empty

makeCheckpoint :: [(String, Maybe String)] -> FilePath -> BS.ByteString -> BS.ByteString -> [BS.ByteString] -> IO BS.ByteString
makeCheckpoint environment directory content base extra = do
    editing <- makeCommit environment directory content [base] "Content"
    makeCommit environment directory content (base : editing : extra) "Checkpoint"

setRef :: [(String, Maybe String)] -> FilePath -> BS.ByteString -> BS.ByteString -> IO ()
setRef environment directory uuid oid = do
    _ <- ok environment directory ["update-ref", BSC.unpack ("refs/heads/" <> uuid), BSC.unpack oid] BS.empty
    pure ()

initialized :: [(String, Maybe String)] -> String -> ObjectFormat -> (FilePath -> IO a) -> IO a
initialized environment backend format action = withTempDirectory $ \directory -> do
    _ <-
        ok
            environment
            directory
            ["init", "-q", "--initial-branch=main", "--ref-format=" ++ backend, "--object-format=" ++ formatName format]
            BS.empty
    action directory
  where
    formatName Sha1 = "sha1"
    formatName Sha256 = "sha256"

inspect :: [(String, Maybe String)] -> FilePath -> Maybe NodeId -> IO InspectionReport
inspect environment directory selected = inspectState native directory environment selected >>= expectRight

valid :: InspectionReport -> IO ()
valid report = do
    assertEqual [] (reportProblems report)
    _ <- expectRight (reportManagedState report)
    pure ()

invokeCli :: [(String, Maybe String)] -> FilePath -> [String] -> IO GitResult
invokeCli environment directory arguments = do
    candidate <- findExecutable "git-roam" >>= maybe (fail "Cabal did not expose git-roam") makeAbsolute
    runGit (nativeGit candidate) (GitInvocation directory arguments BS.empty environment) >>= expectRight

main :: IO ()
main = do
    environment <- fixtureEnvironment
    runTests $
        [ ("decode stored commit headers and binary tree entries", decoderTest)
        , ("missing branch versus missing retained version", closureTest environment)
        , ("old and merged dependencies remain required", mergedDependencyTest environment)
        , ("canonical branch names must match history identity", identityTest environment)
        , ("same UUID conflicts across local and dependency histories", rootConflictTest environment)
        , ("Node scope excludes unrelated invalid histories", scopeTest environment)
        , ("missing reachable blob is not accepted", missingBlobTest environment)
        , ("missing commit is not silently omitted", missingCommitTest environment)
        , ("replace refs do not rewrite inspected history", replaceTest environment)
        , ("grafts cannot hide missing older payload", graftTest environment)
        , ("shallow history is reported as incomplete", shallowTest environment)
        , ("read-only inspection preserves index, files and refs", readOnlyTest environment)
        , ("main, moved linked and detached worktree status", worktreeTest environment)
        , ("bare repository inspection", bareTest environment)
        , ("symbolic Node branches are diagnosed", symbolicRefTest environment)
        , ("changed refs override a transient closure failure", changingRefsTest environment)
        , ("ordinary transitions preserve every formal Checkpoint", transitionTest environment)
        , ("CLI check/status and Node inference", cliTest environment)
        ]
            ++ [ ("real history matrix " ++ backend ++ " " ++ show format, matrixTest environment backend format)
               | backend <- ["files", "reftable"]
               , format <- [Sha1, Sha256]
               ]

decoderTest :: IO ()
decoderTest = forM_ [Sha1, Sha256] $ \format -> do
    let oid = BS.replicate (objectIdLength format) 97
        raw = BS.replicate (objectIdLength format `div` 2) 170
    decoded <- expectRight (decodeCommit format ("tree " <> oid <> "\nparent " <> oid <> "\ngpgsig fixture\n continuation\n\nmessage\0"))
    assertEqual [objectId format oid] (commitParents decoded)
    entries <- expectRight (decodeTree format ("100644 name\nwith newline\0" <> raw))
    assertEqual [TreeEntry "name\nwith newline" RegularFile (objectId format oid)] entries
    expectLeft (decodeTree format ("100644 .roam\0" <> BS.take 2 raw))
    expectLeft (decodeTree format ("100600 .roam\0" <> raw))
    expectLeft (decodeCommit format ("tree " <> oid))
    expectLeft (decodeCommit format ("tree " <> oid <> "\nparent invalid\n\nmessage"))

matrixTest :: [(String, Maybe String)] -> String -> ObjectFormat -> IO ()
matrixTest environment backend format = initialized environment backend format $ \directory -> do
    empty <- inspect environment directory Nothing
    valid empty
    assertEqual [] (reportNodes empty)
    (b, bt, _) <- makeRoot environment directory uuidB "B Root"
    bk <- makeCheckpoint environment directory bt b []
    setRef environment directory uuidB bk
    (a, at, _) <- makeRoot environment directory uuidA "A Root"
    ak <- makeCheckpoint environment directory at a [bk]
    setRef environment directory uuidA ak
    report <- inspect environment directory Nothing
    valid report
    assertEqual 2 (length (reportNodes report))
    let nodes = Map.fromList [(viewNode n, n) | n <- reportNodes report]
    aView <- maybe (fail "Missing Node A") pure (Map.lookup (nodeId uuidA) nodes)
    assertEqual (Just (objectId format ak)) (viewLatestCheckpoint aView)
    assertEqual (Map.singleton (nodeId uuidB) (objectId format bk)) (viewDependencies aView)
    -- A noncanonical ordinary ref is unrelated even if it points to Node history.
    _ <- ok environment directory ["update-ref", "refs/heads/notes", BSC.unpack a] BS.empty
    inspect environment directory Nothing >>= valid

closureTest :: [(String, Maybe String)] -> IO ()
closureTest environment = initialized environment "files" Sha1 $ \directory -> do
    (b, bt, _) <- makeRoot environment directory uuidB "B Root"
    bk <- makeCheckpoint environment directory bt b []
    (a, at, _) <- makeRoot environment directory uuidA "A Root"
    ak <- makeCheckpoint environment directory at a [bk]
    setRef environment directory uuidA ak
    _ <- ok environment directory ["update-ref", "-d", BSC.unpack ("refs/heads/" <> uuidB)] BS.empty
    absent <- inspect environment directory Nothing
    assertEqual [MissingDependencyBranch (objectId Sha1 ak) (nodeId uuidB) (objectId Sha1 bk)] (reportProblems absent)
    cliFailure <- invokeCli environment directory ["check"]
    assertEqual (ExitFailure 1) (gitExitCode cliFailure)
    assertTrue "Missing branch diagnostic lost" ("missing-node-branch:" `BS.isInfixOf` gitStderr cliFailure)
    cliStatus <- invokeCli environment directory ["status"]
    assertEqual (ExitFailure 1) (gitExitCode cliStatus)
    assertTrue "Status omitted the actual Node" (uuidA `BS.isInfixOf` gitStdout cliStatus)
    -- The object is still reachable through A, but Root does not retain B's K.
    setRef environment directory uuidB b
    old <- inspect environment directory Nothing
    assertEqual [DependencyVersionNotRetained (objectId Sha1 ak) (nodeId uuidB) (objectId Sha1 bk)] (reportProblems old)
    setRef environment directory uuidB bk
    inspect environment directory Nothing >>= valid

mergedDependencyTest :: [(String, Maybe String)] -> IO ()
mergedDependencyTest environment = initialized environment "files" Sha1 $ \directory -> do
    (b, bt, _) <- makeRoot environment directory uuidB "B"
    bk <- makeCheckpoint environment directory bt b []
    (a, at, _) <- makeRoot environment directory uuidA "A"
    side <- makeCheckpoint environment directory at a [bk]
    editing <- makeCommit environment directory at [a] "other Content"
    mainK <- makeCommit environment directory at [a, editing] "other Checkpoint"
    merged <- makeCheckpoint environment directory at mainK [side]
    latest <- makeCheckpoint environment directory at merged []
    setRef environment directory uuidA latest
    report <- inspect environment directory Nothing
    assertEqual [DependencyVersionNotRetained (objectId Sha1 side) (nodeId uuidB) (objectId Sha1 bk)] (reportProblems report)
    setRef environment directory uuidB bk
    fixed <- inspect environment directory Nothing
    valid fixed
    let aViews = filter ((== nodeId uuidA) . viewNode) (reportNodes fixed)
    assertEqual [4] (map viewFormalCount aViews)

identityTest :: [(String, Maybe String)] -> IO ()
identityTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, _, _) <- makeRoot environment directory uuidA "A"
    setRef environment directory uuidB a
    report <- inspect environment directory Nothing
    assertEqual [RefIdentityMismatch (nodeId uuidB) (nodeId uuidA) (objectId Sha1 a)] (reportProblems report)

rootConflictTest :: [(String, Maybe String)] -> IO ()
rootConflictTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, at, _) <- makeRoot environment directory uuidA "A Root 1"
    other <- makeCommit environment directory at [] "A Root 2"
    otherK <- makeCheckpoint environment directory at other []
    (c, ct, _) <- makeRoot environment directory uuidC "C"
    ck <- makeCheckpoint environment directory ct c [otherK]
    setRef environment directory uuidC ck
    setRef environment directory uuidA a
    outcome <- inspectState native directory environment Nothing
    case outcome of
        Left (HistoryFailure (ConflictingRoots _ _ _)) -> pure ()
        otherResult -> fail ("Lost Root conflict: " ++ show otherResult)

scopeTest :: [(String, Maybe String)] -> IO ()
scopeTest environment = initialized environment "files" Sha1 $ \directory -> do
    _ <- makeRoot environment directory uuidA "A"
    blob <- line <$> ok environment directory ["hash-object", "-w", "--stdin"] "not a commit"
    -- Git rejects blob branch tips, so use an ordinary Git commit with an empty tree.
    empty <- line <$> ok environment directory ["mktree"] BS.empty
    invalid <- makeCommit environment directory empty [] (BSC.unpack blob)
    setRef environment directory uuidC invalid
    inspect environment directory (Just (nodeId uuidA)) >>= valid
    outcome <- inspectState native directory environment Nothing
    case outcome of
        Left (HistoryFailure (InvalidNodeTree _ _)) -> pure ()
        other -> fail ("Unrelated malformed Node was hidden: " ++ show other)

removeLoose :: FilePath -> BS.ByteString -> IO ()
removeLoose directory oid = do
    let text = BSC.unpack oid
        path = directory </> ".git" </> "objects" </> take 2 text </> drop 2 text
    exists <- doesFileExist path
    assertTrue "Fixture object was not loose" exists
    removeFile path

missingBlobTest :: [(String, Maybe String)] -> IO ()
missingBlobTest environment = initialized environment "files" Sha1 $ \directory -> do
    (_, _, marker) <- makeRoot environment directory uuidA "A"
    removeLoose directory marker
    outcome <- inspectState native directory environment Nothing
    case outcome of
        Left (MissingReachableObjects missing) -> assertEqual [marker] missing
        other -> fail ("Missing blob was accepted: " ++ show other)

missingCommitTest :: [(String, Maybe String)] -> IO ()
missingCommitTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, _, _) <- makeRoot environment directory uuidA "A"
    removeLoose directory a
    outcome <- inspectState native directory environment Nothing
    expectLeft outcome

replaceTest :: [(String, Maybe String)] -> IO ()
replaceTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, _, _) <- makeRoot environment directory uuidA "A"
    (b, _, _) <- makeRoot environment directory uuidB "B"
    _ <- ok environment directory ["replace", BSC.unpack a, BSC.unpack b] BS.empty
    inspect environment directory Nothing >>= valid

graftTest :: [(String, Maybe String)] -> IO ()
graftTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, _, oldMarker) <- makeRoot environment directory uuidA "A"
    newMarker <- line <$> ok environment directory ["hash-object", "-w", "--stdin"] "new marker\n"
    contents <- line <$> ok environment directory ["mktree"] ("100644 blob " <> newMarker <> "\t.roam\n")
    top <- line <$> ok environment directory ["mktree"] ("040000 tree " <> contents <> "\t" <> uuidA <> "\n")
    w <- makeCommit environment directory top [a] "Content"
    setRef environment directory uuidA w
    BS.writeFile (directory </> ".git/info/grafts") (w <> "\n")
    removeLoose directory oldMarker
    outcome <- inspectState native directory environment Nothing
    case outcome of
        Left (MissingReachableObjects missing) -> assertEqual [oldMarker] missing
        other -> fail ("Graft hid incomplete stored history: " ++ show other)

shallowTest :: [(String, Maybe String)] -> IO ()
shallowTest environment = initialized environment "files" Sha1 $ \directory -> withTempDirectory $ \destination -> do
    (a, at, _) <- makeRoot environment directory uuidA "A"
    w <- makeCommit environment directory at [a] "Content"
    setRef environment directory uuidA w
    let clone = destination </> "shallow"
    _ <- ok environment directory ["clone", "-q", "--no-local", "--depth=1", "-b", BSC.unpack uuidA, directory, clone] BS.empty
    result <- inspectState native clone environment Nothing
    assertEqual (Left ShallowRepository) result
    incomplete <- invokeCli environment clone ["check"]
    assertEqual (ExitFailure 3) (gitExitCode incomplete)
    assertTrue "Incomplete history diagnostic lost" ("history-incomplete:" `BS.isInfixOf` gitStderr incomplete)

readOnlyTest :: [(String, Maybe String)] -> IO ()
readOnlyTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, at, _) <- makeRoot environment directory uuidA "A"
    w <- makeCommit environment directory at [a] "Content"
    setRef environment directory uuidA w
    _ <- ok environment directory ["switch", "-q", BSC.unpack uuidA] BS.empty
    let note = directory </> BSC.unpack uuidA </> "note.org"
    writeFile note "staged\n"
    _ <- ok environment directory ["add", "--", note] BS.empty
    writeFile note "unstaged\n"
    writeFile (directory </> "untracked") "user data\n"
    indexBefore <- BS.readFile (directory </> ".git/index")
    refsBefore <- ok environment directory ["show-ref"] BS.empty
    report <- inspect environment directory Nothing
    valid report
    assertEqual [True] [case viewKind n of Content _ _ -> True; _ -> False | n <- reportNodes report]
    BS.readFile (directory </> ".git/index") >>= assertEqual indexBefore
    BS.readFile note >>= assertEqual "unstaged\n"
    BS.readFile (directory </> "untracked") >>= assertEqual "user data\n"
    ok environment directory ["show-ref"] BS.empty >>= assertEqual refsBefore

worktreeTest :: [(String, Maybe String)] -> IO ()
worktreeTest environment = initialized environment "files" Sha1 $ \directory -> withTempDirectory $ \outside -> do
    (a, _, _) <- makeRoot environment directory uuidA "A"
    _ <- makeRoot environment directory uuidB "B"
    _ <- ok environment directory ["switch", "-q", BSC.unpack uuidA] BS.empty
    let original = outside </> "linked space"
        moved = outside </> "moved\nlinked"
        detached = outside </> "detached"
    _ <- ok environment directory ["worktree", "add", "-q", original, BSC.unpack uuidB] BS.empty
    _ <- ok environment directory ["worktree", "move", original, moved] BS.empty
    _ <- ok environment directory ["worktree", "add", "-q", "--detach", detached, BSC.unpack a] BS.empty
    report <- inspect environment directory Nothing
    valid report
    assertEqual 3 (length (reportWorktrees report))
    let movedPaths = [worktreePath w | w <- reportWorktrees report, worktreeNode w == Just (nodeId uuidB)]
    assertEqual [Encoding.encodeUtf8 (Text.pack moved)] movedPaths
    assertEqual [True] [worktreeIsMain w | w <- reportWorktrees report, worktreeNode w == Just (nodeId uuidA)]
    assertEqual 1 (length [w | w <- reportWorktrees report, worktreeNode w == Nothing])

bareTest :: [(String, Maybe String)] -> IO ()
bareTest environment = initialized environment "files" Sha1 $ \directory -> withTempDirectory $ \outside -> do
    _ <- makeRoot environment directory uuidA "A"
    let bare = outside </> "bare.git"
    _ <- ok environment directory ["clone", "-q", "--bare", directory, bare] BS.empty
    inspect environment bare Nothing >>= valid

symbolicRefTest :: [(String, Maybe String)] -> IO ()
symbolicRefTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, _, _) <- makeRoot environment directory uuidA "A"
    _ <- ok environment directory ["update-ref", "refs/heads/notes", BSC.unpack a] BS.empty
    _ <- ok environment directory ["symbolic-ref", BSC.unpack ("refs/heads/" <> uuidA), "refs/heads/notes"] BS.empty
    result <- inspectState native directory environment Nothing
    assertEqual (Left (SymbolicNodeBranch (nodeId uuidA) "refs/heads/notes")) result

changingRefsTest :: [(String, Maybe String)] -> IO ()
changingRefsTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, at, _) <- makeRoot environment directory uuidA "A"
    (b, bt, _) <- makeRoot environment directory uuidB "B"
    bk <- makeCheckpoint environment directory bt b []
    ak <- makeCheckpoint environment directory at a [bk]
    setRef environment directory uuidA ak
    counter <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            outcome <- runGit native invocation
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    n <- atomicModifyIORef' counter (\count -> (count + 1, count))
                    pure $ if n == 1 then fmap (\result -> result{gitStdout = gitStdout result <> "refs/heads/" <> uuidC <> "\0" <> a <> "\0\n"}) outcome else outcome
                else pure outcome
    result <- inspectState racing directory environment Nothing
    assertEqual (Left ReferencesChanged) result

transitionTest :: [(String, Maybe String)] -> IO ()
transitionTest environment = initialized environment "files" Sha1 $ \directory -> do
    (a, at, _) <- makeRoot environment directory uuidA "A"
    k <- makeCheckpoint environment directory at a []
    w <- makeCommit environment directory at [k] "Content 1"
    setRef environment directory uuidA w
    before <- reportManagedState <$> inspect environment directory Nothing >>= expectRight
    other <- makeCommit environment directory at [k] "Content 2"
    setRef environment directory uuidA other
    afterContent <- reportManagedState <$> inspect environment directory Nothing >>= expectRight
    assertEqual (Right ()) (validateOrdinaryTransition before afterContent)
    setRef environment directory uuidA a
    afterReset <- reportManagedState <$> inspect environment directory Nothing >>= expectRight
    assertTrue "Unreferenced Checkpoint was discarded by an ordinary update" $
        case validateOrdinaryTransition before afterReset of
            Left [CheckpointsDiscarded node _] -> node == nodeId uuidA
            _ -> False
    _ <- ok environment directory ["update-ref", "-d", BSC.unpack ("refs/heads/" <> uuidA)] BS.empty
    afterDelete <- reportManagedState <$> inspect environment directory Nothing >>= expectRight
    assertEqual (Left [NodeBranchRemoved (nodeId uuidA)]) (validateOrdinaryTransition afterReset afterDelete)
    alternateRoot <- makeCommit environment directory at [] "another Root"
    setRef environment directory uuidA alternateRoot
    changedRoot <- reportManagedState <$> inspect environment directory Nothing >>= expectRight
    assertTrue "Root replacement was accepted" $
        case validateOrdinaryTransition afterReset changedRoot of
            Left [NodeRootChanged _ _ _] -> True
            _ -> False

cliTest :: [(String, Maybe String)] -> IO ()
cliTest environment = initialized environment "files" Sha1 $ \directory -> do
    let cli = invokeCli environment directory
    empty <- cli ["check"]
    assertEqual ExitSuccess (gitExitCode empty)
    assertTrue "Missing empty repository summary" ("OK: 0 Nodes" `BS.isPrefixOf` gitStdout empty)
    (a, at, _) <- makeRoot environment directory uuidA "A"
    k <- makeCheckpoint environment directory at a []
    w <- makeCommit environment directory at [k] "unconfirmed"
    setRef environment directory uuidA w
    _ <- ok environment directory ["switch", "-q", BSC.unpack uuidA] BS.empty
    status <- cli ["status"]
    assertEqual ExitSuccess (gitExitCode status)
    assertTrue "Content dependencies incorrectly declared empty" ("dependencies of latest Checkpoint: none" `BS.isInfixOf` gitStdout status)
    assertTrue "Content tail missing" ("content-tail yes" `BS.isInfixOf` gitStdout status)
    assertTrue "Main worktree not distinguished" ("main; not a removable deployment" `BS.isInfixOf` gitStdout status)
    checked <- cli ["check", "--node", BSC.unpack uuidA]
    assertEqual ExitSuccess (gitExitCode checked)
    bad <- cli ["check", "--node", "bad"]
    assertEqual (ExitFailure 2) (gitExitCode bad)
    -- Encoding must not truncate Unicode into canonical ASCII UUID bytes.
    nonAscii <- cli ["check", "--node", replicate 8 '\305' ++ "-1111-4111-8111-111111111111"]
    assertEqual (ExitFailure 2) (gitExitCode nonAscii)
