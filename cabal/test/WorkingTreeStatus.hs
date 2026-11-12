{-# LANGUAGE OverloadedStrings #-}

module WorkingTreeStatus (workingTreeTests) where

import qualified Codec.CBOR.Read as CBOR
import qualified Codec.CBOR.Term as CBOR
import Control.Exception (IOException, bracket_, catch, displayException)
import Control.Monad (forM_, unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf)
import qualified Data.Set as Set
import qualified GitRoam.Application.Status as App
import GitRoam.Application.Worktree (planRemovalFor)
import GitRoam.Git
import qualified GitRoam.Git.Status as Working
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Output
import GitRoam.Protocol.Identity (NodeId, nodeIdBytes)
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath, encodePath)
import System.Directory (canonicalizePath, createDirectory, removeFile, renameDirectory, renameFile)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, (</>))
import TestSupport
import WorktreeFixture

workingTreeTests :: [(String, IO ())]
workingTreeTests =
    [ ("porcelain v2 tracks record boundaries, conflicts and submodules", parser)
    , ("porcelain v2 rejects malformed/truncated records", malformed)
    ]
        ++ [("native worktree status and independent removal safety " ++ backend ++ " " ++ show format, fixture backend format (\git executable repo parent -> byteSafe (nativeChanges git executable repo parent))) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("native submodule summary ignores ignore overrides " ++ backend ++ " " ++ show format, fixture backend format (submodules format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("status rejects replaced worktree identities and retains partial reports " ++ backend ++ " " ++ show format, fixture backend format (identities format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("status costs, failures and readonly process environment " ++ backend ++ " " ++ show format, fixture backend format costs) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
        ++ [("relative linked-worktree registration and backlink identity " ++ backend ++ " " ++ show format, fixture backend format (relativeWorktrees format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

summary :: Bool -> Bool -> Bool -> Bool -> Working.WorkingTreeStatus
summary = Working.WorkingTreeStatus

clean :: Working.WorkingTreeStatus
clean = summary False False False False

byteSafe :: IO () -> IO ()
byteSafe action = catch action (\problem -> fail (show (displayException (problem :: IOException))))

ordinary :: ObjectFormat -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
ordinary format xy sub path = "1 " <> xy <> " " <> sub <> " 100644 100644 100644 " <> oid <> " " <> oid <> " " <> path <> "\0"
  where
    oid = BS.replicate (objectIdLength format) 97

renamed :: ObjectFormat -> BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
renamed format kind path original = "2 " <> kind <> ". N... 100644 100644 100644 " <> oid <> " " <> oid <> " " <> kind <> "100 " <> path <> "\0" <> original <> "\0"
  where
    oid = BS.replicate (objectIdLength format) 98

unmerged :: ObjectFormat -> BS.ByteString -> BS.ByteString
unmerged format xy = "u " <> xy <> " N... 100644 100644 100644 100644 " <> oid <> " " <> oid <> " " <> oid <> " conflict\0"
  where
    oid = BS.replicate (objectIdLength format) 99

parser :: IO ()
parser = forM_ [Sha1, Sha256] $ \format -> do
    let parse expected bytes = expectRight (Working.decodeWorkingTreeStatus format bytes) >>= assertEqual expected
        raw = "space \n" <> BS.pack [255]
    parse clean ""
    parse clean "# unknown future header\0! ignored\0"
    parse (summary True False False False) (ordinary format "M." "N..." raw)
    parse (summary False True False False) (ordinary format ".T" "N..." raw)
    parse (summary True True True False) (ordinary format "AM" "N..." raw <> "? other\nfile\0")
    forM_ ["R", "C"] $ \kind -> parse (summary True False False False) (renamed format kind raw "? original is opaque\n")
    forM_ ["DD", "AU", "UD", "UA", "DU", "AA", "UU"] $ \xy -> parse (summary False False False True) (unmerged format xy)
    parse (summary False True False False) (ordinary format ".." "SC.." raw)
    parse (summary False True False False) (ordinary format ".." "S.M." raw)
    parse (summary False True True False) (ordinary format ".M" "S..U" raw)
    parse (summary True True True True) (ordinary format "M." "SCMU" raw <> unmerged format "UU")

malformed :: IO ()
malformed = forM_ [Sha1, Sha256] $ \format -> do
    let good = ordinary format "M." "N..." "path"
        rename = renamed format "R" "new" "old"
    forM_ ["? unterminated", "? \0", "\0", "x unknown\0", "1 M. N...\0", BS.init good, good <> "\0", ordinary format "ZZ" "N..." "path", ordinary format ".." "N..." "path", ordinary format "M." "SXXX" "path", BS.take (BS.length rename - 4) rename, "2 R. N... 100644 100644 100644 bad bad R100 new\0old\0", unmerged format "M.", renamed format "Z" "new" "old"] $ expectLeft . Working.decodeWorkingTreeStatus format
    expectLeft (Working.decodeWorkingTreeStatus (if format == Sha1 then Sha256 else Sha1) good)

request :: [App.NodeProperty] -> App.StatusQuery
request props = App.NodeStatusQuery App.AllNodes (App.SelectedProperties (Set.fromList props))

report :: Git IO -> FilePath -> [App.NodeProperty] -> IO App.StatusReport
report git repo props = App.queryStatus git repo (request props) >>= expectRight

rows :: App.StatusReport -> IO [App.NodeStatus]
rows (App.NodesReport values _) = pure values
rows _ = fail "Expected Node report"

nodeRow :: NodeId -> App.StatusReport -> IO App.NodeStatus
nodeRow node value = rows value >>= \values -> case filter ((== node) . App.statusNode) values of [row] -> pure row; _ -> fail "Missing/duplicate Node row"

expectSummary :: NodeId -> Working.WorkingTreeStatus -> App.StatusReport -> IO ()
expectSummary node expected value = do
    assertEqual [] (App.reportDiagnostics value)
    row <- nodeRow node value
    case App.statusWorkingTrees row of App.Available [App.WorktreeStatus _ (Just actual)] -> assertEqual expected actual; _ -> fail (show row)

nativeChanges :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeChanges git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    rawParent <- encodePath parent
    path <- decodePath (rawParent <> "/work tree\n" <> BS.pack [255])
    let temporaryPath = parent </> "initial-worktree"
    manual git repo temporaryPath nodeA
    renameDirectory temporaryPath path
    _ <- ok git path ["worktree", "repair"] ""
    let check expected = report git repo [App.StatusProperty] >>= expectSummary nodeA expected
    initial <- report git repo [App.StatusProperty]
    expectSummary nodeA clean initial
    b <- nodeRow nodeB initial
    assertEqual (App.Available []) (App.statusWorkingTrees b)
    a <- nodeRow nodeA initial
    assertEqual App.NotRequested (App.statusWorktrees a)
    expectedPath <- encodePath path
    case App.statusWorkingTrees a of App.Available [App.WorktreeStatus actual _] -> assertEqual expectedPath actual; _ -> fail "Missing byte path"
    case statusValue initial of Object [("nodes", Array [Object fields, _]), _] -> assertEqual ["node", "status"] (map fst fields); _ -> fail "Status-only selection changed worktrees output"
    -- Ignored data and operation markers can coexist with Git-clean status.
    BS.writeFile (parent </> "excludes") "ignored\n"
    _ <- ok git repo ["config", "core.excludesFile", parent </> "excludes"] ""
    BS.writeFile (path </> "ignored") "user data"
    check clean
    state <- snapshot git repo
    ignored <- planRemovalFor git repo state (Set.singleton nodeA)
    case ignored of Left problem -> assertTrue "Ignored-file protection was bypassed" ("Dirty or ignored worktree data" `isInfixOf` problem); Right _ -> fail "Ignored data was considered removable"
    removeFile (path </> "ignored")
    mergeMarker <- BSC.init <$> ok git path ["rev-parse", "--path-format=absolute", "--git-path", "MERGE_HEAD"] ""
    markerPath <- decodePath mergeMarker
    headBytes <- ok git path ["rev-parse", "HEAD"] ""
    BS.writeFile markerPath headBytes
    check clean
    ongoing <- planRemovalFor git repo state (Set.singleton nodeA)
    case ongoing of Left problem -> assertTrue "Ongoing-operation protection was bypassed" ("In-progress Git operation" `isInfixOf` problem); Right _ -> fail "MERGE_HEAD was considered removable"
    removeFile markerPath
    relative <- decodePath (nodeIdBytes nodeA <> "/file \n" <> BS.pack [254])
    relativeBytes <- encodePath relative
    BS.writeFile (path </> relative) "initial\n"
    check (summary False False True False)
    text <- cli executable repo TextFormat
    assertEqual ExitSuccess (gitExitCode text)
    assertEqual BS.empty (gitStderr text)
    assertTrue "Text status omitted dirty/untracked flags" ("dirty" `BS.isInfixOf` gitStdout text && "untracked yes" `BS.isInfixOf` gitStdout text)
    _ <- ok git path ["--literal-pathspecs", "add", "--pathspec-from-file=-", "--pathspec-file-nul"] (relativeBytes <> "\0")
    check (summary True False False False)
    BS.appendFile (path </> relative) "changed\n"
    check (summary True True False False)
    _ <- ok git path ["--literal-pathspecs", "add", "--pathspec-from-file=-", "--pathspec-file-nul"] (relativeBytes <> "\0")
    _ <- ok git path ["commit", "-qm", "fixture content"] ""
    BS.appendFile (path </> relative) "unstaged\n"
    check (summary False True False False)
    _ <- ok git path ["--literal-pathspecs", "add", "--pathspec-from-file=-", "--pathspec-file-nul"] (relativeBytes <> "\0")
    _ <- ok git path ["commit", "-qm", "fixture update"] ""
    let destination = BSC.unpack (nodeIdBytes nodeA) </> "renamed\nfile"
    renameFile (path </> relative) (path </> destination)
    destinationBytes <- encodePath destination
    _ <- ok git path ["--literal-pathspecs", "add", "--all", "--pathspec-from-file=-", "--pathspec-file-nul"] (relativeBytes <> "\0" <> destinationBytes <> "\0")
    check (summary True False False False)
    _ <- ok git path ["commit", "-qm", "fixture rename"] ""
    forM_ [JsonFormat, CborFormat] $ \wire -> do
        current <- report git repo [App.StatusProperty]
        result <- cli executable repo wire
        assertEqual ExitSuccess (gitExitCode result)
        assertEqual BS.empty (gitStderr result)
        assertEqual (encodeValue wire (statusValue current)) (gitStdout result)
    let conflict = nodeIdBytes nodeA <> "/conflict \n" <> BS.pack [253]
    versions <- mapM (ok git path ["hash-object", "-w", "--stdin"]) ["base", "ours", "theirs"]
    let entries = BS.concat ["100644 " <> BSC.init oid <> " " <> BSC.pack (show stage) <> "\t" <> conflict <> "\0" | (stage, oid) <- zip [1 :: Int ..] versions]
    _ <- ok git path ["update-index", "-z", "--index-info"] entries
    conflictPath <- decodePath conflict
    BS.writeFile (path </> conflictPath) "conflicted content"
    check (summary False False False True)

relativeWorktrees :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
relativeWorktrees format git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    expected <- inspectRepository git repo [] >>= expectRight
    common <- decodePath (repositoryCommonDirectory expected) >>= canonicalizePath
    forM_ [(nodeA, True), (nodeB, False)] $ \(node, explicit) -> do
        let path = parent </> (if explicit then "relative-flag" else "relative-config")
        unless explicit $ do
            _ <- ok git repo ["config", "worktree.useRelativePaths", "true"] ""
            pure ()
        _ <- ok git repo (["worktree", "add"] ++ ["--relative-paths" | explicit] ++ ["--", path, BSC.unpack (nodeIdBytes node)]) ""
        actual <- inspectRepository git path [] >>= expectRight
        admin <- decodePath (repositoryGitDirectory actual) >>= canonicalizePath
        rawPath <- encodePath path
        assertEqual (Just rawPath) (repositoryWorktree actual)
        assertEqual format (repositoryObjectFormat actual)
        decodePath (repositoryCommonDirectory actual) >>= canonicalizePath >>= assertEqual common
        -- Verify Git really wrote relative paths and native discovery resolved
        -- both .git and commondir. Do not duplicate discovery in production.
        dot <- BS.readFile (path </> ".git")
        forward <- maybe (fail "missing gitdir header") pure (BS.stripPrefix "gitdir: " dot >>= BS.stripSuffix "\n") >>= decodePath
        assertEqual False (isAbsolute forward)
        canonicalizePath (path </> forward) >>= assertEqual admin
        commonLink <- BS.readFile (admin </> "commondir") >>= terminatedPath
        assertEqual False (isAbsolute commonLink)
        canonicalizePath (admin </> commonLink) >>= assertEqual common
        original <- BS.readFile (admin </> "gitdir")
        backlink <- terminatedPath original
        assertEqual False (isAbsolute backlink)
        own <- canonicalizePath (path </> ".git")
        canonicalizePath (admin </> backlink) >>= assertEqual own
        let check summaryValue = forM_ [repo, path] $ \from -> report git from [App.StatusProperty] >>= expectSummary node summaryValue
        check clean
        BS.writeFile (path </> "untracked") "user data"
        check (summary False False True False)
        removeFile (path </> "untracked")
        check clean
        -- Corrupt the backlink after Git returns registration, so the query
        -- must reject the registered path itself rather than merely discover
        -- that a newly reported path is absent.
        bad <- encodePath (backlink ++ "-wrong")
        let damaged = Git $ \invocation -> do
                result <- runGit git invocation
                if all (`elem` gitArguments invocation) ["worktree", "list"]
                    then BS.writeFile (admin </> "gitdir") (bad <> "\n")
                    else pure ()
                pure result
        bracket_
            (pure ())
            (BS.writeFile (admin </> "gitdir") original)
            ( do
                value <- report damaged repo [App.StatusProperty]
                row <- nodeRow node value
                case App.statusWorkingTrees row of App.Available [App.WorktreeStatus found Nothing] -> assertEqual rawPath found; _ -> fail (show row)
                let diagnostics = App.reportDiagnostics value
                assertEqual [(Just node, Just App.StatusProperty, Just rawPath)] [(App.diagnosticNode d, App.diagnosticProperty d, App.diagnosticPath d) | d <- diagnostics]
                assertTrue "backlink identity check was bypassed" (any ((== "Worktree administration points to another path") . App.statusMessage) diagnostics)
            )
        check clean
        Worktrees.listWorktrees git repo format >>= expectRight >>= \records -> assertTrue "relative registration was lost" (any ((== rawPath) . Worktrees.treePath) records)
  where
    terminatedPath bytes = maybe (fail "missing path terminator") decodePath (BS.stripSuffix "\n" bytes)

submodules :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
submodules format git _ repo parent = do
    root git repo nodeA
    let path = parent </> "node"
        source = parent </> "source"
        moduleName = BSC.unpack (nodeIdBytes nodeA) </> "module"
    manual git repo path nodeA
    createDirectory source
    _ <- ok git source ["init", "-q", "--object-format=" ++ if format == Sha1 then "sha1" else "sha256"] ""
    BS.writeFile (source </> "tracked") "base\n"
    _ <- ok git source ["add", "tracked"] ""
    _ <- ok git source ["commit", "-qm", "submodule root"] ""
    _ <- ok git path ["-c", "protocol.file.allow=always", "submodule", "add", "--", source, moduleName] ""
    _ <- ok git path ["commit", "-qam", "add submodule"] ""
    let check expected = report git repo [App.StatusProperty] >>= expectSummary nodeA expected
        child = path </> moduleName
    check clean
    _ <- ok git repo ["config", "submodule." ++ moduleName ++ ".ignore", "all"] ""
    _ <- ok git repo ["config", "diff.ignoreSubmodules", "all"] ""
    BS.writeFile (child </> "untracked") "untracked\n"
    check (summary False True True False)
    removeFile (child </> "untracked")
    BS.appendFile (child </> "tracked") "modified\n"
    check (summary False True False False)
    _ <- ok git child ["commit", "-qam", "child change"] ""
    check (summary False True False False)
    _ <- ok git path ["add", "--", moduleName] ""
    check (summary True False False False)

identities :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
identities format git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    let a = parent </> "a"
        b = parent </> "b"
    manual git repo a nodeA
    manual git repo b nodeB
    _ <- ok git repo ["worktree", "lock", "--reason", "fixture lock", b] ""
    original <- BS.readFile (a </> ".git")
    other <- BS.readFile (b </> ".git")
    let partial = do
            value <- report git repo [App.TipProperty, App.WorktreesProperty, App.StatusProperty]
            aRow <- nodeRow nodeA value
            bRow <- nodeRow nodeB value
            case App.statusWorkingTrees aRow of App.Available [App.WorktreeStatus _ Nothing] -> pure (); _ -> fail (show aRow)
            case App.statusWorkingTrees bRow of App.Available [App.WorktreeStatus _ (Just result)] -> assertEqual clean result; _ -> fail (show bRow)
            case App.statusTip aRow of App.Available _ -> pure (); _ -> fail "Lost independently readable tip"
            case App.statusWorktrees aRow of App.Available [_] -> pure (); _ -> fail "Lost independently readable registration"
            raw <- encodePath a
            let issues = App.reportDiagnostics value
            assertEqual [(Just nodeA, Just App.StatusProperty, Just raw)] [(App.diagnosticNode item, App.diagnosticProperty item, App.diagnosticPath item) | item <- issues]
            pure value
    BS.writeFile (a </> ".git") other
    _ <- partial
    BS.writeFile (a </> ".git") original
    removeFile (a </> ".git")
    _ <- partial
    BS.writeFile (a </> ".git") original
    -- Same common dir, branch and OID still do not prove the worktree identity.
    let alias = parent </> "same-node"
    _ <- ok git repo ["worktree", "add", "--force", alias, BSC.unpack (nodeIdBytes nodeA)] ""
    aliasMetadata <- BS.readFile (alias </> ".git")
    BS.writeFile (a </> ".git") aliasMetadata
    aliasReport <- report git repo [App.StatusProperty]
    aliasRow <- nodeRow nodeA aliasReport
    rawA <- encodePath a
    rawAlias <- encodePath alias
    case App.statusWorkingTrees aliasRow of
        App.Available values -> assertEqual [(rawA, Nothing), (rawAlias, Just clean)] [(App.statusWorktreePath value, App.statusWorktreeSummary value) | value <- values]
        _ -> fail (show aliasRow)
    assertEqual [Just rawA] (map App.diagnosticPath (App.reportDiagnostics aliasReport))
    BS.writeFile (a </> ".git") original
    _ <- ok git repo ["worktree", "remove", alias] ""
    -- Replace an existing registered path by an unrelated, clean repository.
    renameDirectory a (parent </> "saved-a")
    createDirectory a
    _ <- ok git a ["init", "-q", "--separate-git-dir=" ++ (parent </> "foreign-admin"), "--object-format=" ++ if format == Sha1 then "sha1" else "sha256"] ""
    _ <- ok git a ["commit", "--allow-empty", "-qm", "foreign clean repository"] ""
    _ <- partial
    renameDirectory a (parent </> "foreign")
    -- Missing directory is prunable registration, not an empty status set.
    missing <- partial
    forM_ [JsonFormat, CborFormat] $ \wire -> do
        result <- cli executable repo wire
        assertEqual (ExitFailure 3) (gitExitCode result)
        assertEqual BS.empty (gitStderr result)
        let bytes = gitStdout result
        if wire == JsonFormat
            then do
                _ <- expectRight (Aeson.eitherDecodeStrict' bytes :: Either String Aeson.Value)
                assertTrue "Unavailable booleans were not null" ("\"staged\":null" `BS.isInfixOf` bytes)
            else do
                (rest, _) <- expectRight (CBOR.deserialiseFromBytes CBOR.decodeTerm (BL.fromStrict bytes))
                assertEqual BL.empty rest
    assertTrue "Missing path failure was hidden" (not (null (App.reportDiagnostics missing)))
    renameDirectory (parent </> "saved-a") a
    -- A lasting identity change after the status process invalidates its result.
    changed <- newIORef False
    let racing = Git $ \invocation -> do
            result <- runGit git invocation
            if "status" `elem` gitArguments invocation && gitDirectory invocation == a then BS.writeFile (a </> ".git") other >> modifyIORef' changed (const True) else pure ()
            pure result
    race <- report racing repo [App.StatusProperty]
    readIORef changed >>= assertEqual True
    row <- nodeRow nodeA race
    assertEqual [Nothing] [App.statusWorktreeSummary value | App.Available values <- [App.statusWorkingTrees row], value <- values]
    BS.writeFile (a </> ".git") original
    -- The main worktree is also a valid target when it checks out a Node.
    _ <- ok git repo ["worktree", "remove", a] ""
    _ <- ok git repo ["checkout", BSC.unpack (nodeIdBytes nodeA)] ""
    report git repo [App.StatusProperty] >>= expectSummary nodeA clean

costs :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
costs git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    let a = parent </> "a"
        b = parent </> "b"
    manual git repo a nodeA
    manual git repo b nodeB
    calls <- newIORef []
    let traced = observeGit (\invocation -> modifyIORef' calls (++ [invocation])) git
    selected <- App.queryStatus traced repo (App.NodeStatusQuery (App.SelectedNodes (Set.singleton nodeA)) (App.SelectedProperties (Set.fromList [App.StatusProperty, App.WorktreesProperty]))) >>= expectRight
    expectSummary nodeA clean selected
    observed <- readIORef calls
    assertEqual 1 (length [() | call <- observed, "worktree" `elem` gitArguments call])
    let statusCalls = [call | call <- observed, "status" `elem` gitArguments call]
    assertEqual [a] (map gitDirectory statusCalls)
    forM_ statusCalls $ \call -> do
        assertTrue "Optional index locks enabled" ("--no-optional-locks" `elem` gitArguments call)
        assertEqual (Just (Just a)) (lookup "GIT_WORK_TREE" (reverse (gitEnvironment call)))
        case lookup "GIT_DIR" (reverse (gitEnvironment call)) of Just (Just _) -> pure (); _ -> fail "Git directory not pinned"
    assertEqual [] [gitArguments call | call <- observed, any (`elem` gitArguments call) ["cat-file", "rev-list", "fsck"]]
    admin <- BSC.init <$> ok git a ["rev-parse", "--path-format=absolute", "--git-dir"] ""
    adminPath <- decodePath admin
    indexBefore <- BS.readFile (adminPath </> "index")
    headBefore <- BS.readFile (adminPath </> "HEAD")
    refsBefore <- ok git repo ["show-ref"] ""
    -- Force a stat-cache refresh opportunity while keeping the contents clean.
    BS.writeFile (a </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") BS.empty
    let redirected = parent </> "wrong-index"
    BS.writeFile redirected "invalid foreign index"
    old <- lookupEnv "GIT_INDEX_FILE"
    bracket_ (setEnv "GIT_INDEX_FILE" redirected) (maybe (unsetEnv "GIT_INDEX_FILE") (setEnv "GIT_INDEX_FILE") old) $ report (nativeGit defaultGitExecutable) repo [App.StatusProperty] >>= expectSummary nodeA clean
    BS.readFile (adminPath </> "index") >>= assertEqual indexBefore
    BS.readFile (adminPath </> "HEAD") >>= assertEqual headBefore
    BS.readFile (a </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") >>= assertEqual BS.empty
    ok git repo ["show-ref"] "" >>= assertEqual refsBefore
    forM_ [request [App.TipProperty], request [App.WorktreesProperty], request [App.RemoteProperty], App.NodeStatusQuery App.AllNodes App.DefaultProperties] $ \query -> do
        modifyIORef' calls (const [])
        result <- App.queryStatus traced repo query >>= expectRight
        assertEqual [] (App.reportDiagnostics result)
        readIORef calls >>= \values -> assertEqual [] [gitArguments call | call <- values, "status" `elem` gitArguments call]
    let broken = Git $ \invocation -> if "status" `elem` gitArguments invocation && gitDirectory invocation == a then pure (Right (GitResult ExitSuccess "1 truncated\0" "")) else runGit git invocation
    incomplete <- report broken repo [App.StatusProperty]
    assertEqual 1 (length (App.reportDiagnostics incomplete))
    bRow <- nodeRow nodeB incomplete
    case App.statusWorkingTrees bRow of App.Available [App.WorktreeStatus _ (Just value)] -> assertEqual clean value; _ -> fail "Partial failure discarded B"
    let noRegistration = Git $ \invocation -> if "worktree" `elem` gitArguments invocation then pure (Left (GitTransportError "fixture registration failure")) else runGit git invocation
    unavailable <- report noRegistration repo [App.StatusProperty]
    unavailableRows <- rows unavailable
    forM_ unavailableRows $ \row -> assertEqual App.Unavailable (App.statusWorkingTrees row)

cli :: FilePath -> FilePath -> OutputFormat -> IO GitResult
cli executable repo wire = do
    let name = case wire of JsonFormat -> "json"; CborFormat -> "cbor"; TextFormat -> "text"
    result <- runGit (nativeGit executable) (GitInvocation repo ["--format", name, "status", "-t", "node", "-p", "status"] BS.empty [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]) >>= expectRight
    unless (gitExitCode result `elem` [ExitSuccess, ExitFailure 3]) (fail (show result))
    pure result
