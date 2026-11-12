{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified GitRoam.Application.Deploy as Deploy
import qualified GitRoam.Application.Inspect as Inspect
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Worktree (planDeployment)
import GitRoam.Git
import GitRoam.Git.Refs
import GitRoam.Git.Worktrees (listWorktrees, treePath, worktreeNode)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Directory (doesDirectoryExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runTests $
        [ ("canonical local identities and remote suffix recognition", identities)
        , ("byte-safe refs retain ordering and symbolic targets", observations)
        , ("malformed, duplicate and object-format-invalid refs fail closed", malformed)
        , ("one ref enumeration preserves invocation and failure evidence", adapter)
        ]
            ++ [("native batch refs and worktree observations " ++ backend ++ " " ++ show format, fixture backend format (nativeObservations format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]
            ++ [("Inspect, Deploy and Worktree retain symbolic-ref policies " ++ backend ++ " " ++ show format, fixture backend format (strictPolicies format)) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

strictDecode :: ObjectFormat -> NodeRefScope -> BS.ByteString -> Either RefReadError [NodeRefObservation]
strictDecode format scope = requireCompleteRefs . decodeNodeRefs format scope

strictRead :: Git IO -> FilePath -> [(String, Maybe String)] -> ObjectFormat -> NodeRefScope -> IO (Either RefReadError [NodeRefObservation])
strictRead git directory environment format scope = requireCompleteRefs <$> readNodeRefs git directory environment format scope

local :: NodeId -> BS.ByteString
local node = "refs/heads/" <> nodeIdBytes node

remote :: BS.ByteString -> NodeId -> BS.ByteString
remote prefix node = "refs/remotes/" <> prefix <> "/" <> nodeIdBytes node

row :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
row name oid symbolic = name <> "\0" <> oid <> "\0" <> symbolic <> "\n"

identities :: IO ()
identities = do
    assertEqual (Just nodeA) (localNode (local nodeA))
    forM_ ["00000000-0000-0000-0000-000000000000", "ffffffff-ffff-ffff-ffff-ffffffffffff", "11111111-1111-1111-8111-111111111111"] $ \uuid -> do
        node <- expectRight (parseNodeId uuid)
        assertEqual (Just node) (localNode ("refs/heads/" <> uuid))
    forM_ ["refs/heads/main", "refs/heads/prefix/" <> nodeIdBytes nodeA, "refs/tags/" <> nodeIdBytes nodeA, "refs/heads/AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"] $ assertEqual Nothing . localNode
    assertEqual (Just ("origin", nodeA)) (remoteNodeCandidate (remote "origin" nodeA))
    assertEqual (Just ("origin/nested", nodeA)) (remoteNodeCandidate (remote "origin/nested" nodeA))
    forM_ [local nodeA, "refs/remotes/" <> nodeIdBytes nodeA, "refs/remotes/origin/main", remote "origin" nodeA <> "/extra"] $ assertEqual Nothing . remoteNodeCandidate

observations :: IO ()
observations = forM_ [Sha1, Sha256] $ \format -> do
    let oid = BS.replicate (objectIdLength format) 49
        rawPrefix = "origin/" <> BS.pack [255]
        a = row (local nodeA) oid "refs/heads/main"
        b = row (local nodeB) oid ""
        r = row (remote rawPrefix nodeA) oid (remote "backup" nodeA)
        ordinary = row "refs/heads/main" "ignored" ""
    records <- expectRight (strictDecode format LocalAndRemoteNodes (b <> ordinary <> r <> a))
    assertEqual [local nodeB, remote rawPrefix nodeA, local nodeA] (map observedRef records)
    assertEqual [nodeB, nodeA, nodeA] (map observedNode records)
    assertEqual [Nothing, Just rawPrefix, Nothing] (map observedRemotePrefix records)
    assertEqual ["", remote "backup" nodeA, "refs/heads/main"] (map observedSymbolic records)
    assertEqual [oid, oid, oid] (map (objectIdBytes . observedTip) records)
    locals <- expectRight (strictDecode format LocalNodes (b <> r <> a))
    assertEqual [local nodeB, local nodeA] (map observedRef locals)
    assertEqual (Right []) (strictDecode format LocalNodes "")

malformed :: IO ()
malformed = forM_ [Sha1, Sha256] $ \format -> do
    let oid = BS.replicate (objectIdLength format) 49
        good = row (local nodeA) oid ""
    forM_ ["broken\n", local nodeA <> "\0" <> oid <> "\n", local nodeA <> "\0" <> oid <> "\0\0\n", "\n"] $ \bytes ->
        case strictDecode format LocalNodes bytes of
            Left (MalformedRefOutput _) -> pure ()
            other -> fail ("Malformed row was accepted: " ++ show other)
    forM_ [BS.replicate (objectIdLength format) 48, BS.replicate (objectIdLength format) 103, BS.replicate (if format == Sha1 then 64 else 40) 49] $ \bad ->
        case strictDecode format LocalNodes (row (local nodeA) bad "") of
            Left (InvalidRefObject _ _) -> pure ()
            other -> fail ("Invalid OID was accepted: " ++ show other)
    forM_ [good, row (local nodeA) (BS.replicate (objectIdLength format) 50) ""] $ \duplicate ->
        case strictDecode format LocalNodes (good <> duplicate) of
            Left (DuplicateNodeRef _) -> pure ()
            other -> fail ("Duplicate ref was accepted: " ++ show other)
    expectLeft (strictDecode format LocalAndRemoteNodes (row (remote "origin" nodeA) "bad" ""))

adapter :: IO ()
adapter = do
    calls <- newIORef []
    let environment = [("GIT_NO_LAZY_FETCH", Just "1"), ("GIT_DIR", Nothing)]
        args = "--no-replace-objects" : nodeRefArguments LocalAndRemoteNodes
        invocation = GitInvocation "/repository" args "" environment
        fake result = Git $ \request -> do
            modifyIORef' calls (++ [request])
            pure result
    strictRead (fake (Right (GitResult ExitSuccess "" ""))) "/repository" environment Sha1 LocalAndRemoteNodes >>= assertEqual (Right [])
    readIORef calls >>= assertEqual [invocation]
    let transport = GitTransportError "fixture transport"
        failed = GitResult (ExitFailure 7) "partial" "fixture failure"
        warning = GitResult ExitSuccess (row (local nodeA) (BS.replicate 40 49) "") "warning: omitted broken ref"
    strictRead (fake (Left transport)) "/repository" environment Sha1 LocalNodes >>= assertEqual (Left (RefTransportFailure transport))
    forM_ [failed, warning] $ \result ->
        strictRead (fake (Right result)) "/repository" environment Sha1 LocalNodes >>= assertEqual (Left (RefCommandFailure result))

nativeObservations :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
nativeObservations format git _ repo parent = do
    root git repo nodeA
    root git repo nodeB
    a <- BSC.init <$> ok git repo ["rev-parse", BSC.unpack (local nodeA)] ""
    _ <- ok git repo ["branch", "ordinary", BSC.unpack (local nodeA)] ""
    _ <- ok git repo ["update-ref", BSC.unpack (remote "origin/nested" nodeA), BSC.unpack a] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack (remote "backup" nodeA), BSC.unpack (remote "origin/nested" nodeA)] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack (local nodeB), "refs/heads/ordinary"] ""
    calls <- newIORef []
    let observed = observeGit (\request -> modifyIORef' calls (++ [gitArguments request])) git
    records <- strictRead observed repo [] format LocalAndRemoteNodes >>= expectRight
    readIORef calls >>= assertEqual ["--no-replace-objects" : nodeRefArguments LocalAndRemoteNodes]
    assertEqual [local nodeA, local nodeB, remote "backup" nodeA, remote "origin/nested" nodeA] (map observedRef records)
    assertEqual ["", "refs/heads/ordinary", remote "origin/nested" nodeA, ""] (map observedSymbolic records)
    assertEqual [a, a, a, a] (map (objectIdBytes . observedTip) records)
    locals <- strictRead git repo [] format LocalNodes >>= expectRight
    assertEqual [local nodeA, local nodeB] (map observedRef locals)
    let target = parent </> "worktree with space"
    manual git repo target nodeA
    trees <- listWorktrees git repo format >>= expectRight
    assertEqual [Just nodeA] [worktreeNode tree | tree <- trees, treePath tree == BSC.pack target]

strictPolicies :: ObjectFormat -> Git IO -> FilePath -> FilePath -> FilePath -> IO ()
strictPolicies format git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    state <- snapshot git repo
    _ <- ok git repo ["branch", "ordinary", BSC.unpack (local nodeB)] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack (local nodeB), "refs/heads/ordinary"] ""
    enable git executable repo
    -- The OID is unchanged: Worktree must still reject the symbolic ref even
    -- though its map of Node identities and tips would match the trusted state.
    facts <- strictRead git repo [] format LocalNodes >>= expectRight
    assertEqual ["", "refs/heads/ordinary"] (map observedSymbolic facts)
    Inspect.inspectState git repo [] Nothing >>= assertEqual (Left (Inspect.SymbolicNodeBranch nodeB "refs/heads/ordinary"))
    _ <- Inspect.inspectState git repo [] (Just nodeA) >>= expectRight
    let target = parent </> "refused"
    planDeployment git repo state target >>= expectLeft
    Deploy.deploy executable git repo target Nothing >>= expectLeft
    doesDirectoryExist target >>= assertEqual False
    -- A symbolic remote candidate must also remain unacceptable to Deploy,
    -- including when the underlying Node is already present locally.
    _ <- ok git repo (ownHookBypass ++ ["symbolic-ref", "--delete", BSC.unpack (local nodeB)]) ""
    b <- ok git repo ["rev-parse", "ordinary"] ""
    _ <- ok git repo (ownHookBypass ++ ["update-ref", BSC.unpack (local nodeB), BSC.unpack (BSC.init b)]) ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack (remote "origin" nodeA), BSC.unpack (local nodeA)] ""
    Deploy.deploy executable git repo target Nothing >>= expectLeft
    doesDirectoryExist target >>= assertEqual False
