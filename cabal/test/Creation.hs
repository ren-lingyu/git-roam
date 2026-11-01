{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import GitRoam.Application.Create
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Cli (Command (..), HelpTopic (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects (nativeHistorySource)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import GitRoam.Worktree.Paths (shortName)
import System.Directory (createDirectory, doesDirectoryExist, doesFileExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        [("Node creation CLI requires an explicit path", arguments)]
            ++ [("Root and editable worktree " ++ backend ++ " " ++ show format, fixture backend format lifecycle) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ ("default generation creates distinct UUIDv4 identities", fixture "files" Sha1 generation)
               , ("Node create deploys only the new Node", fixture "files" Sha1 existingNodes)
               , ("an existing main Node does not block a new identity", fixture "files" Sha1 existingMain)
               , ("an unrelated locked deployment is retained", fixture "files" Sha1 existingLocked)
               , ("local, fetched, tag and configuration conflicts refuse", fixture "files" Sha1 conflicts)
               , ("unsafe paths refuse before objects or refs are written", fixture "files" Sha1 unsafePath)
               , ("native author/committer errors precede object writes", fixture "files" Sha1 identities)
               , ("clean checkout failure compensates the new branch", fixture "files" Sha1 cleanFailure)
               , ("dirty checkout failure preserves user files and identity", fixture "files" Sha1 dirtyFailure)
               , ("changed Content history survives creation failure", fixture "files" Sha1 changedHistory)
               , ("conditional creation preserves a competing same-OID branch", fixture "files" Sha1 competingCreation)
               , ("conditional creation protects existing ref state", fixture "files" Sha1 changedExisting)
               , ("public create and ordinary Git editing form a local loop", fixture "files" Sha1 cliLoop)
               , ("creation requires protection and a UUIDv4 source", fixture "files" Sha1 prerequisites)
               ]

arguments :: IO ()
arguments = do
    assertEqual (Right (CreateNode "work")) (parseCommand ["node", "create", "--path", "work"])
    assertEqual (Right (ShowHelp NodeCreateHelp)) (parseCommand ["help", "node", "create"])
    forM_ [["node", "create"], ["node", "create", "--path", ""], ["node", "create", "--uuid", BSC.unpack (nodeIdBytes nodeA), "--path", "work"], ["node", "create", "--path", "work", "extra"]] $ expectLeft . parseCommand

create :: Git IO -> FilePath -> FilePath -> FilePath -> IO (Either CreationFailure CreationResult)
create git executable repo path = createNodeWith (pure nodeA) executable git repo path

lifecycle :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
lifecycle git executable repo parent = do
    enable git executable repo
    before <- ok git repo ["status", "--porcelain=v1", "-z"] ""
    result <- create git executable repo (parent </> "work") >>= expectRight
    assertEqual nodeA (createdNode result)
    assertEqual (parent </> "work" </> shortName nodeA) (createdPath result)
    formatName <- BSC.init <$> ok git repo ["rev-parse", "--show-object-format"] ""
    format <- expectRight (parseObjectFormat formatName)
    let provider = nativeHistorySource git repo format []
    commit <- loadCommit provider (createdRoot result) >>= expectRight
    assertEqual [] (commitParents commit)
    top <- loadTree provider (commitTree commit) >>= expectRight
    assertEqual [nodeIdBytes nodeA] (map entryName top)
    assertEqual [Directory] (map entryMode top)
    inner <- case top of [entry] -> loadTree provider (entryObject entry) >>= expectRight; _ -> fail "Invalid Root"
    assertEqual [".roam"] (map entryName inner)
    assertEqual [RegularFile] (map entryMode inner)
    BS.readFile (createdPath result </> BSC.unpack (nodeIdBytes nodeA) </> ".roam") >>= assertEqual BS.empty
    state <- snapshot git repo
    assertEqual (Just (createdRoot result)) (Map.lookup nodeA (managedRefs state))
    after <- ok git repo ["status", "--porcelain=v1", "-z"] ""
    assertEqual before after
    _ <- ok git (createdPath result) ["commit", "--allow-empty", "-m", "Content"] ""
    _ <- snapshot git repo
    upstream <- ok git repo ["for-each-ref", "--format=%(upstream)", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA)] ""
    assertEqual "\n" upstream

generation :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
generation git executable repo parent = do
    enable git executable repo
    a <- createNode executable git repo (parent </> "work") >>= expectRight
    b <- createNode executable git repo (parent </> "work") >>= expectRight
    assertTrue "UUID reused" (createdNode a /= createdNode b)
    forM_ [a, b] $ \result -> do
        let uuid = nodeIdBytes (createdNode result)
        assertEqual 52 (BS.index uuid 14)
        assertTrue "Invalid UUID variant" (BS.index uuid 19 `elem` [56, 57, 97, 98])

existingNodes :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
existingNodes git executable repo parent = do
    root git repo nodeB
    before <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB)] ""
    enable git executable repo
    _ <- create git executable repo (parent </> "work") >>= expectRight
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual [nodeA] [node | record <- records, Just node <- [worktreeNode record]]
    after <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB)] ""
    assertEqual before after

conflicts :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
conflicts git executable repo parent = do
    root git repo nodeB
    b <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB)] ""
    let remote = BSC.unpack ("refs/remotes/origin/" <> nodeIdBytes nodeA)
        tag = BSC.unpack ("refs/tags/" <> nodeIdBytes nodeA)
        key = "branch." ++ BSC.unpack (nodeIdBytes nodeA) ++ ".remote"
        path = parent </> "work"
    enable git executable repo
    _ <- ok git repo ["update-ref", remote, BSC.unpack b] ""
    create git executable repo path >>= expectLeft
    _ <- ok git repo ["update-ref", "-d", remote] ""
    _ <- ok git repo ["update-ref", tag, BSC.unpack b] ""
    create git executable repo path >>= expectLeft
    _ <- ok git repo ["update-ref", "-d", tag] ""
    _ <- ok git repo ["config", key, "origin"] ""
    create git executable repo path >>= expectLeft
    _ <- ok git repo ["config", "--unset-all", key] ""
    let orphan = parent </> "orphan"
    manual git repo orphan nodeB
    _ <- ok git orphan ["symbolic-ref", "HEAD", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA)] ""
    create git executable repo path >>= expectLeft
    _ <- ok git orphan ["symbolic-ref", "HEAD", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB)] ""
    _ <- create git executable repo path >>= expectRight
    before <- snapshot git repo
    create git executable repo path >>= expectLeft
    snapshot git repo >>= assertEqual before

existingMain :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
existingMain git executable repo parent = do
    root git repo nodeB
    _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeB)] ""
    writeFile (repo </> "user-file") "keep"
    enable git executable repo
    _ <- create git executable repo (parent </> "work") >>= expectRight
    readFile (repo </> "user-file") >>= assertEqual "keep"
    headRef <- ok git repo ["symbolic-ref", "HEAD"] ""
    assertEqual ("refs/heads/" <> nodeIdBytes nodeB <> "\n") headRef

existingLocked :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
existingLocked git executable repo parent = do
    root git repo nodeB
    let path = parent </> "work"; old = path </> shortName nodeB
    manual git repo old nodeB
    _ <- ok git repo ["worktree", "lock", old] ""
    writeFile (old </> "user-file") "keep"
    enable git executable repo
    _ <- create git executable repo path >>= expectRight
    readFile (old </> "user-file") >>= assertEqual "keep"
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual [Just ""] [treeLocked r | r <- records, worktreeNode r == Just nodeB]

unsafePath :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
unsafePath git executable repo parent = do
    enable git executable repo
    before <- ok git repo ["count-objects"] ""
    let path = parent </> "work"
    createDirectory path
    writeFile (path </> "user") "keep"
    create git executable repo path >>= expectLeft
    create git executable repo (repo </> "not-ignored") >>= expectLeft
    ok git repo ["count-objects"] "" >>= assertEqual before
    readFile (path </> "user") >>= assertEqual "keep"

identities :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
identities git executable repo parent = do
    enable git executable repo
    _ <- ok git repo ["config", "user.useConfigOnly", "true"] ""
    before <- ok git repo ["count-objects"] ""
    forM_ [["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"], ["GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"]] $ \names -> do
        let missing = Git $ \invocation -> runGit git invocation{gitEnvironment = gitEnvironment invocation ++ [(name, Nothing) | name <- names]}
        create missing executable repo (parent </> "work") >>= expectLeft
        ok git repo ["count-objects"] "" >>= assertEqual before
    snapshot git repo >>= assertEqual Map.empty . managedRefs

hook :: Git IO -> FilePath -> String -> IO ()
hook git repo script = do
    _ <- ok git repo ["config", "hook.fail-create.event", "post-checkout"] ""
    _ <- ok git repo ["config", "hook.fail-create.command", script] ""
    pure ()

cleanFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cleanFailure git executable repo parent = do
    enable git executable repo
    hook git repo "false"
    create git executable repo (parent </> "work") >>= expectLeft
    snapshot git repo >>= assertEqual Map.empty . managedRefs
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual 1 (length records)

dirtyFailure :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
dirtyFailure git executable repo parent = do
    enable git executable repo
    let path = parent </> "work"; file = path </> shortName nodeA </> "user"
    hook git repo ("printf user > '" ++ file ++ "'; false")
    create git executable repo path >>= expectLeft
    readFile file >>= assertEqual "user"
    state <- snapshot git repo
    assertEqual [nodeA] (Map.keys (managedRefs state))

changedHistory :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
changedHistory git executable repo parent = do
    enable git executable repo
    let changing = Git $ \invocation -> do
            result <- runGit git invocation
            if "worktree" `elem` gitArguments invocation && "add" `elem` gitArguments invocation
                then do
                    let branch = BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA)
                    old <- BSC.init <$> ok git repo ["rev-parse", branch] ""
                    tree <- BSC.init <$> ok git repo ["rev-parse", branch ++ "^{tree}"] ""
                    edited <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack tree, "-p", BSC.unpack old, "-m", "User Content"] ""
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", branch, BSC.unpack edited, BSC.unpack old]) ""
                    pure result
                else pure result
    create changing executable repo (parent </> "work") >>= expectLeft
    records <- listWorktrees git repo Sha1 >>= expectRight
    assertEqual 1 (length [r | r <- records, worktreeNode r == Just nodeA])
    tip <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeA)] ""
    parents <- ok git repo ["rev-list", "--parents", "-1", BSC.unpack tip] ""
    assertEqual 2 (length (BSC.words parents))
    _ <- snapshot git repo
    pure ()

competingCreation :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
competingCreation git executable repo parent = do
    enable git executable repo
    let racing = Git $ \invocation -> do
            if "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation
                then do
                    _ <- runGit git invocation >>= expectRight
                    runGit git invocation
                else runGit git invocation
    create racing executable repo (parent </> "work") >>= expectLeft
    snapshot git repo >>= assertEqual [nodeA] . Map.keys . managedRefs

changedExisting :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
changedExisting git executable repo parent = do
    root git repo nodeB
    old <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB)] ""
    tree <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (nodeIdBytes nodeB) ++ "^{tree}"] ""
    edited <- BSC.init <$> ok git repo ["commit-tree", BSC.unpack tree, "-p", BSC.unpack old, "-m", "User Content"] ""
    enable git executable repo
    let racing = Git $ \invocation -> do
            if "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation
                then do
                    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), BSC.unpack edited, BSC.unpack old]) ""
                    runGit git invocation
                else runGit git invocation
    create racing executable repo (parent </> "work") >>= expectLeft
    state <- snapshot git repo
    assertEqual [nodeB] (Map.keys (managedRefs state))
    assertEqual [edited] (map objectIdBytes (Map.elems (managedRefs state)))

cliLoop :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
cliLoop git executable repo _ = do
    _ <- ok git repo ["config", "user.name", "Fixture"] ""
    _ <- ok git repo ["config", "user.email", "fixture@example.invalid"] ""
    writeFile (repo </> ".gitignore") "/nodes/\n"
    enable git executable repo
    inherited <- getEnvironment
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")]
        cli args = runGit (nativeGit executable) (GitInvocation repo args "" environment) >>= expectRight
    result <- cli ["node", "create", "--path", "nodes"]
    assertEqual ExitSuccess (gitExitCode result)
    node <- case BSC.words (BSC.takeWhile (/= '\n') (gitStdout result)) of
        ["node", uuid] -> expectRight (parseNodeId uuid)
        _ -> fail (show result)
    let target = repo </> "nodes" </> shortName node
        note = BSC.unpack (nodeIdBytes node) </> "note.org"
    doesFileExist (target </> BSC.unpack (nodeIdBytes node) </> ".roam") >>= assertEqual True
    writeFile (target </> note) "A real note\n"
    _ <- ok git target ["add", "--", note] ""
    _ <- ok git target ["commit", "-m", "Content"] ""
    checked <- cli ["check"]
    assertEqual ExitSuccess (gitExitCode checked)
    removed <- cli ["undeploy"]
    assertEqual ExitSuccess (gitExitCode removed)
    doesDirectoryExist target >>= assertEqual False

prerequisites :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
prerequisites git executable repo parent = do
    create git executable repo (parent </> "work") >>= expectLeft
    enable git executable repo
    let notV4 = either error id (parseNodeId "11111111-1111-1111-8111-111111111111")
    createNodeWith (pure notV4) executable git repo (parent </> "work") >>= expectLeft
    snapshot git repo >>= assertEqual Map.empty . managedRefs
