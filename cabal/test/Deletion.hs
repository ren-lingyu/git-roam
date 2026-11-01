{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (bracket)
import Control.Monad (forM_, unless)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Delete
import GitRoam.Application.Discard (previewDiscard, previewPlanId)
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Cli (Command (..), HelpTopic (..), parseCommand)
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Directory (doesDirectoryExist)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (BufferMode (NoBuffering), hClose, hFlush, hGetChar, hPutStrLn, hSetBuffering)
import System.Posix.IO (fdToHandle)
import System.Posix.Terminal (openPseudoTerminal)
import System.Process (CreateProcess (..), StdStream (..), proc, waitForProcess, withCreateProcess)
import System.Timeout (timeout)
import TestSupport
import WorktreeFixture

type Case = Git IO -> FilePath -> FilePath -> FilePath -> IO ()

oidText :: ObjectId -> String
oidText = BSC.unpack . objectIdBytes

ref :: NodeId -> String
ref node = BSC.unpack ("refs/heads/" <> nodeIdBytes node)

tip :: Git IO -> FilePath -> NodeId -> IO ObjectId
tip git repo node = do
    bytes <- BSC.init <$> ok git repo ["rev-parse", ref node] ""
    expectRight (parseObjectId (if BS.length bytes == 40 then Sha1 else Sha256) bytes)

putTip :: Git IO -> FilePath -> NodeId -> ObjectId -> IO ()
putTip git repo node oid = ok git repo ["update-ref", ref node, oidText oid] "" >> pure ()

newRoot :: Git IO -> FilePath -> NodeId -> IO ObjectId
newRoot git repo node = root git repo node >> tip git repo node

commit :: Git IO -> FilePath -> ObjectId -> [ObjectId] -> BS.ByteString -> IO ObjectId
commit git repo parent parents message = do
    let format = if BS.length (objectIdBytes parent) == 40 then Sha1 else Sha256
    object <- loadCommit (nativeHistorySource git repo format []) parent >>= expectRight
    bytes <- BSC.init <$> ok git repo (["commit-tree", oidText (commitTree object)] ++ concatMap (\p -> ["-p", oidText p]) parents ++ ["-F", "-"]) message
    expectRight (parseObjectId format bytes)

content :: Git IO -> FilePath -> ObjectId -> BS.ByteString -> IO ObjectId
content git repo parent = commit git repo parent [parent]

version :: Git IO -> FilePath -> ObjectId -> [ObjectId] -> BS.ByteString -> IO (ObjectId, ObjectId)
version git repo parent extra message = do
    w <- content git repo parent (message <> " content")
    k <- commit git repo w (parent : w : extra) message
    pure (k, w)

preview :: Git IO -> FilePath -> NodeId -> IO DeletePreview
preview git repo node = previewDelete git repo node >>= expectRight

identifier :: DeletePreview -> IO BS.ByteString
identifier report = maybe (fail (show report)) pure (deletePlanId report)

isTransaction :: GitInvocation -> Bool
isTransaction invocation = "update-ref" `elem` gitArguments invocation && "--stdin" `elem` gitArguments invocation

main :: IO ()
main =
    runTests $
        [("Node deletion arguments require explicit UUID and complete confirmation", arguments)]
            ++ [("delete Root, Content and Checkpoint histories " ++ backend ++ " " ++ show format, fixture backend format basic) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [ (name, fixture "files" Sha1 action)
               | (name, action) <-
                    [ ("old historical incoming dependency blocks non-cascading deletion", historical)
                    , ("non-first-parent formal history incoming dependency blocks deletion", merged)
                    , ("own outgoing dependencies do not block deletion", outgoing)
                    , ("main, manual and moved linked worktrees block deletion", checkedOut)
                    , ("detached worktree remains untouched", detached)
                    , ("preview is read-only and protection is required only for execution", readOnly)
                    , ("wrong, stale and other-operation plan IDs refuse", stale)
                    , ("local branch configuration is bound and conditionally cleaned", configuration)
                    , ("configuration changes invalidate confirmation", staleConfig)
                    , ("new checkout invalidates confirmation", staleCheckout)
                    , ("incomplete initial managed closure refuses", incomplete)
                    , ("conditional target deletion rejects competing Content update", targetRace)
                    , ("dependency verify rejects competing unrelated ref update", verifyRace)
                    , ("other named Hook continues to protect the transaction", otherHook)
                    , ("lost transaction response reports failure without recreating Node", lostResponse)
                    , ("post-delete configuration failure reports actual state", failedCleanup)
                    , ("noninteractive CLI requires preview-bound confirmation", cli)
                    , ("real terminal confirmation accepts exact plan", interactive True)
                    , ("real terminal refusal leaves Node untouched", interactive False)
                    ]
               ]

arguments :: IO ()
arguments = do
    let uuid = BSC.unpack (nodeIdBytes nodeA)
    assertEqual (Right (PreviewDelete nodeA)) (parseCommand ["node", "delete", "--dry-run", "--node", uuid])
    assertEqual (Right (ExecuteDelete nodeA Nothing)) (parseCommand ["node", "delete", "--node", uuid])
    forM_ [["help", "node", "delete"], ["node", "delete", "--help"], ["node", "delete", "-h"]] $ assertEqual (Right (ShowHelp NodeDeleteHelp)) . parseCommand
    forM_ [["node", "delete"], ["node", "delete", uuid], ["node", "delete", "--node", "bad"], ["node", "delete", "--node", uuid, "--confirm", "yes"], ["node", "delete", "--node", uuid, "--force"], ["node", "delete", "--node", uuid, "--dry-run", "--confirm", replicate 64 'a']] $ expectLeft . parseCommand

basic :: Case
basic git executable repo _ = do
    r <- newRoot git repo nodeA
    rootReport <- preview git repo nodeA
    assertEqual r (deleteRoot rootReport)
    assertEqual Set.empty (deleteVersions rootReport)
    w <- content git repo r "unconfirmed"
    putTip git repo nodeA w
    contentReport <- preview git repo nodeA
    assertEqual (Set.singleton w) (deleteContent contentReport)
    edit <- content git repo w "more Content"
    k <- commit git repo edit [r, edit] "K"
    tailCommit <- content git repo k "tail"
    putTip git repo nodeA tailCommit
    report <- preview git repo nodeA
    assertEqual (Set.singleton k) (deleteVersions report)
    assertEqual (Set.fromList [w, edit, tailCommit]) (deleteContent report)
    before <- snapshot git repo
    enable git executable repo
    token <- identifier report
    _ <- executeDelete executable git repo nodeA token >>= expectRight
    after <- snapshot git repo
    assertEqual (Map.delete nodeA (managedRefs before)) (managedRefs after)
    ok git repo ["cat-file", "-t", oidText k] "" >>= assertEqual "commit\n"

historical :: Case
historical git executable repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (a0, _) <- version git repo ra [] "A"
    (b0, _) <- version git repo rb [a0] "B depends on A"
    (b1, _) <- version git repo b0 [] "B removes current dependency"
    putTip git repo nodeA a0
    putTip git repo nodeB b1
    report <- preview git repo nodeA
    assertEqual [(nodeB, b0, a0)] (deleteIncoming report)
    assertEqual Nothing (deletePlanId report)
    before <- snapshot git repo
    enable git executable repo
    executeDelete executable git repo nodeA (BS.replicate 64 97) >>= expectLeft
    snapshot git repo >>= assertEqual before

merged :: Case
merged git _ repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (a, _) <- version git repo ra [] "A"
    (b, _) <- version git repo rb [] "B main"
    (side, _) <- version git repo rb [a] "B side depends on A"
    (join, _) <- version git repo b [side] "B joins side"
    putTip git repo nodeA a
    putTip git repo nodeB join
    report <- preview git repo nodeA
    assertEqual [(nodeB, side, a)] (deleteIncoming report)
    assertEqual Nothing (deletePlanId report)

outgoing :: Case
outgoing git executable repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (a, _) <- version git repo ra [b] "A depends on B"
    putTip git repo nodeA a
    putTip git repo nodeB b
    before <- snapshot git repo
    token <- preview git repo nodeA >>= identifier
    enable git executable repo
    _ <- executeDelete executable git repo nodeA token >>= expectRight
    after <- snapshot git repo
    assertEqual (Map.delete nodeA (managedRefs before)) (managedRefs after)
    assertEqual (Map.delete nodeA (retainedCheckpoints before)) (retainedCheckpoints after)

checkedOut :: Case
checkedOut git executable repo parent = do
    _ <- newRoot git repo nodeA
    let path = parent </> "manual"
        moved = parent </> "moved"
    manual git repo path nodeA
    forM_ [path, moved] $ \location -> do
        if location == moved then ok git repo ["worktree", "move", path, moved] "" >> pure () else pure ()
        report <- preview git repo nodeA
        assertEqual Nothing (deletePlanId report)
        assertEqual 1 (length (deleteWorktrees report))
        doesDirectoryExist location >>= assertEqual True
    _ <- ok git repo ["worktree", "remove", moved] ""
    _ <- ok git repo ["switch", BSC.unpack (nodeIdBytes nodeA)] ""
    report <- preview git repo nodeA
    assertEqual Nothing (deletePlanId report)
    enable git executable repo
    executeDelete executable git repo nodeA (BS.replicate 64 97) >>= expectLeft

detached :: Case
detached git executable repo parent = do
    r <- newRoot git repo nodeA
    let path = parent </> "detached"
    _ <- ok git repo ["worktree", "add", "--detach", path, oidText r] ""
    token <- preview git repo nodeA >>= identifier
    enable git executable repo
    _ <- executeDelete executable git repo nodeA token >>= expectRight
    doesDirectoryExist path >>= assertEqual True
    ok git path ["rev-parse", "HEAD"] "" >>= assertEqual (objectIdBytes r <> "\n")

readOnly :: Case
readOnly git executable repo _ = do
    _ <- newRoot git repo nodeA
    let reading = Git $ \invocation -> do
            assertTrue "Preview attempted mutation" (not (any (`elem` gitArguments invocation) ["update-ref", "--unset-all", "commit-tree"]))
            runGit git invocation
    before <- snapshot git repo
    token <- preview reading repo nodeA >>= identifier
    executeDelete executable git repo nodeA token >>= expectLeft
    snapshot git repo >>= assertEqual before

stale :: Case
stale git executable repo _ = do
    r <- newRoot git repo nodeA
    (k, _) <- version git repo r [] "K"
    putTip git repo nodeA k
    token <- preview git repo nodeA >>= identifier
    discardToken <- previewDiscard git repo [oidText k] >>= expectRight >>= maybe (fail "No discard plan") pure . previewPlanId
    enable git executable repo
    forM_ [BS.replicate 64 97, discardToken] $ \wrong -> executeDelete executable git repo nodeA wrong >>= expectLeft
    w <- content git repo k "later content"
    putTip git repo nodeA w
    executeDelete executable git repo nodeA token >>= expectLeft
    tip git repo nodeA >>= assertEqual w

configuration :: Case
configuration git executable repo _ = do
    r <- newRoot git repo nodeA
    let key = "branch." ++ BSC.unpack (nodeIdBytes nodeA) ++ ".description"
    _ <- ok git repo ["config", "--add", key, "literal [.*]\nsecond line"] ""
    _ <- ok git repo ["config", "--add", key, "other"] ""
    _ <- ok git repo ["config", "branch.unrelated.description", "keep"] ""
    _ <- ok git repo ["update-ref", "refs/remotes/origin/" ++ BSC.unpack (nodeIdBytes nodeA), oidText r] ""
    report <- preview git repo nodeA
    assertEqual [BSC.pack key, BSC.pack key] (deleteConfigKeys report)
    token <- identifier report
    enable git executable repo
    _ <- executeDelete executable git repo nodeA token >>= expectRight
    ok git repo ["config", "--get", "branch.unrelated.description"] "" >>= assertEqual "keep\n"
    ok git repo ["rev-parse", "refs/remotes/origin/" ++ BSC.unpack (nodeIdBytes nodeA)] "" >>= assertEqual (objectIdBytes r <> "\n")
    found <- runGit git (GitInvocation repo ["config", "--get-all", key] "" []) >>= expectRight
    assertEqual (ExitFailure 1) (gitExitCode found)

staleConfig :: Case
staleConfig git executable repo _ = do
    _ <- newRoot git repo nodeA
    token <- preview git repo nodeA >>= identifier
    _ <- ok git repo ["config", "branch." ++ BSC.unpack (nodeIdBytes nodeA) ++ ".description", "new"] ""
    enable git executable repo
    executeDelete executable git repo nodeA token >>= expectLeft
    _ <- snapshot git repo
    pure ()

staleCheckout :: Case
staleCheckout git executable repo parent = do
    _ <- newRoot git repo nodeA
    token <- preview git repo nodeA >>= identifier
    manual git repo (parent </> "later") nodeA
    enable git executable repo
    executeDelete executable git repo nodeA token >>= expectLeft
    doesDirectoryExist (parent </> "later") >>= assertEqual True

incomplete :: Case
incomplete git _ repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    (b, _) <- version git repo rb [] "B"
    (a, _) <- version git repo ra [b] "A"
    putTip git repo nodeA a
    _ <- ok git repo ["update-ref", "-d", ref nodeB] ""
    previewDelete git repo nodeA >>= expectLeft

targetRace :: Case
targetRace = race nodeA

verifyRace :: Case
verifyRace = race nodeB

race :: NodeId -> Case
race target git executable repo _ = do
    ra <- newRoot git repo nodeA
    rb <- newRoot git repo nodeB
    let old = if target == nodeA then ra else rb
    w <- content git repo old "competing Content"
    token <- preview git repo nodeA >>= identifier
    enable git executable repo
    let racing = Git $ \invocation -> do
            if isTransaction invocation then ok git repo (ownHookBypass ++ ["update-ref", ref target, oidText w, oidText old]) "" >> pure () else pure ()
            runGit git invocation
    executeDelete executable racing repo nodeA token >>= expectLeft
    state <- snapshot git repo
    assertEqual (Just (if target == nodeA then w else ra)) (Map.lookup nodeA (managedRefs state))
    tip git repo target >>= assertEqual w
    assertTrue "Target was partially deleted" (Map.member nodeA (managedRefs state))

otherHook :: Case
otherHook git executable repo _ = do
    r <- newRoot git repo nodeA
    enable git executable repo
    _ <- ok git repo ["config", "hook.audit.event", "reference-transaction"] ""
    _ <- ok git repo ["config", "hook.audit.command", "false"] ""
    token <- preview git repo nodeA >>= identifier
    executeDelete executable git repo nodeA token >>= expectLeft
    tip git repo nodeA >>= assertEqual r

lostResponse :: Case
lostResponse git executable repo _ = do
    _ <- newRoot git repo nodeA
    enable git executable repo
    token <- preview git repo nodeA >>= identifier
    let losing = Git $ \invocation -> do
            result <- runGit git invocation
            pure (if isTransaction invocation then Left (GitTransportError "lost deletion response") else result)
    result <- executeDelete executable losing repo nodeA token
    case result of
        Left (DeleteFailure _ details) -> assertTrue "Actual outcome was not reported" (any (isInfixOf "response confirmed: False") details)
        Right value -> fail (show value)
    state <- snapshot git repo
    assertEqual Map.empty (managedRefs state)

failedCleanup :: Case
failedCleanup git executable repo _ = do
    _ <- newRoot git repo nodeA
    _ <- ok git repo ["config", "branch." ++ BSC.unpack (nodeIdBytes nodeA) ++ ".description", "keep on failure"] ""
    token <- preview git repo nodeA >>= identifier
    enable git executable repo
    let failing = Git $ \invocation -> if "--unset-all" `elem` gitArguments invocation then pure (Right (GitResult (ExitFailure 4) "" "")) else runGit git invocation
    result <- executeDelete executable failing repo nodeA token
    case result of
        Left (DeleteFailure _ details) -> assertTrue "Confirmed deletion missing" (any (isInfixOf "response confirmed: True") details)
        Right value -> fail (show value)
    state <- snapshot git repo
    assertEqual Map.empty (managedRefs state)

cliEnvironment :: IO [(String, Maybe String)]
cliEnvironment = do
    inherited <- getEnvironment
    pure ([(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null")])

cli :: Case
cli git executable repo _ = do
    _ <- newRoot git repo nodeA
    environment <- cliEnvironment
    let call parameters = runGit (nativeGit executable) (GitInvocation repo parameters "" environment) >>= expectRight
        args = ["node", "delete", "--node", BSC.unpack (nodeIdBytes nodeA)]
    report <- call (args ++ ["--dry-run"])
    assertEqual ExitSuccess (gitExitCode report)
    assertTrue "Dry-run output missing" ("Read-only Node deletion preview" `BS.isInfixOf` gitStdout report)
    refused <- call args
    assertEqual (ExitFailure 1) (gitExitCode refused)
    enable git executable repo
    token <- preview git repo nodeA >>= identifier
    result <- call (args ++ ["--confirm", BSC.unpack token])
    assertEqual ExitSuccess (gitExitCode result)

interactive :: Bool -> Case
interactive accept git executable repo _ = do
    _ <- newRoot git repo nodeA
    enable git executable repo
    token <- preview git repo nodeA >>= identifier
    environment <- cliEnvironment
    bracket (openPseudoTerminal >>= \(a, b) -> (,) <$> fdToHandle a <*> fdToHandle b) (\(a, b) -> hClose a >> hClose b) $ \(master, slave) -> do
        hSetBuffering master NoBuffering
        hSetBuffering slave NoBuffering
        inherited <- getEnvironment
        let apply values (key, value) = maybe id (\text -> ((key, text) :)) value (filter ((/= key) . fst) values)
            command = (proc executable ["node", "delete", "--node", BSC.unpack (nodeIdBytes nodeA)]){cwd = Just repo, env = Just (foldl apply inherited environment), std_in = UseHandle slave, std_err = UseHandle slave, std_out = CreatePipe}
            readPrompt text = if "Type this plan ID to delete the Node: " `isInfixOf` text then pure text else if length text > 30000 then fail "Oversized preview" else hGetChar master >>= \c -> readPrompt (text ++ [c])
        withCreateProcess command $ \_ output _ process -> do
            observed <- timeout (10 * 1000000) (readPrompt "") >>= maybe (fail "Confirmation prompt timed out") pure
            assertTrue "Plan ID not displayed" (BSC.unpack token `isInfixOf` observed)
            hPutStrLn master (if accept then BSC.unpack token else "decline")
            hFlush master
            bytes <- maybe (fail "No stdout") BS.hGetContents output
            code <- waitForProcess process
            assertEqual (if accept then ExitSuccess else ExitFailure 1) code
            unless (not accept || "Deleted local Node branch" `BS.isInfixOf` bytes) (fail "No deletion result")
    state <- snapshot git repo
    assertEqual (not accept) (Map.member nodeA (managedRefs state))
