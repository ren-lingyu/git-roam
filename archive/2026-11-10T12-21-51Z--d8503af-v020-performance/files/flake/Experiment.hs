{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Exception (evaluate)
import Control.Monad (unless)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Clock (getMonotonicTimeNSec)
import qualified GitRoam.Application.Delete as Delete
import GitRoam.Application.Inspect
import GitRoam.Git
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import System.Environment (getArgs)
import System.Mem (performGC)

fingerprint :: Show a => a -> IO String
fingerprint value = do
    let bytes = SHA256.hash (BSC.pack (show value))
    _ <- evaluate (BS.length bytes)
    pure (BSC.unpack (BS.concatMap hex bytes))
  where
    hex byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48+n else 87+n

require :: Show e => Either e a -> IO a
require = either (fail . show) pure

main :: IO ()
main = do
    args <- getArgs
    case args of
        [executable, directory, mode, targetName, countText] -> do
            let nodes = read countText :: Int
            target <- require (parseNodeId (BSC.pack targetName))
            counts <- newIORef (Map.empty :: Map.Map String Int)
            let native = nativeGit executable
                observe call = do
                    let key
                            | "--batch" `elem` gitArguments call = "batch"
                            | any ("--batch-check" `BSC.isPrefixOf`) (map BSC.pack (gitArguments call)) = "metadata"
                            | otherwise = "other"
                    atomicModifyIORef' counts (\values -> (Map.insertWith (+) key 1 values, ()))
                git = if mode == "inspect-oneshot"
                    then Git (\call -> observe call >> runGit native call)
                    else observeGit observe native
                total = sum . Map.elems <$> readIORef counts
                inspect = do
                    report <- inspectState git directory [] Nothing >>= require
                    state <- require (reportManagedState report)
                    unless (Map.size (managedRefs state) == nodes) (fail "Fixture Node count mismatch")
                    pure (report, state)
                finish started previous semantic full size = do
                    ended <- getMonotonicTimeNSec
                    values <- readIORef counts
                    let count name = Map.findWithDefault 0 name values
                        allProcesses = sum (Map.elems values)
                    putStrLn ("{\"mode\":\""++mode++"\",\"nodes\":"++show nodes
                        ++",\"operation_seconds\":"++show (fromIntegral (ended-started)/1e9 :: Double)
                        ++",\"physical_git_processes\":"++show allProcesses
                        ++",\"timed_git_processes\":"++show (allProcesses-previous)
                        ++",\"batch_processes\":"++show (count "batch")
                        ++",\"metadata_processes\":"++show (count "metadata")
                        ++",\"other_processes\":"++show (count "other")
                        ++",\"result_size\":"++show size
                        ++",\"result_digest\":\""++semantic++"\",\"full_digest\":\""++full++"\"}")
            case mode of
                name | name `elem` ["inspect-oneshot", "inspect-native"] -> do
                    started <- getMonotonicTimeNSec
                    (report, state) <- inspect
                    reachable <- require (reachableHistoryFrom (managedHistory state) (Map.elems (managedRefs state)))
                    digest <- fingerprint (Map.toAscList (managedRefs state), Set.toAscList reachable, reportNodes report)
                    finish started 0 digest digest (Set.size reachable)
                name | name `elem` ["reach-single", "reach-multi"] -> do
                    (_, state) <- inspect
                    let history = managedHistory state
                    oid <- maybe (fail "Target ref missing") pure (Map.lookup target (managedRefs state))
                    fromTarget <- require (reachableHistory history oid)
                    _ <- fingerprint fromTarget
                    let starts = Map.elems (Map.delete target (managedRefs state))
                    performGC
                    previous <- total
                    started <- getMonotonicTimeNSec
                    remaining <- require $ if mode == "reach-single"
                        then Set.unions <$> mapM (reachableHistory history) starts
                        else reachableHistoryFrom history starts
                    let exclusive = fromTarget `Set.difference` remaining
                    digest <- fingerprint (Set.toAscList remaining, Set.toAscList exclusive)
                    finish started previous digest digest (Set.size remaining)
                name | name `elem` ["delete-native", "delete-legacy"] -> do
                    started <- getMonotonicTimeNSec
                    report <- Delete.previewDelete git directory target >>= require
                    unless (null (Delete.deleteProblems report)) (fail "Unsafe deletion preview fixture")
                    full <- fingerprint report
                    semantic <- fingerprint report{Delete.deletePlanId = Nothing}
                    finish started 0 semantic full (Set.size (Delete.deleteExclusiveCommits report))
                _ -> fail "Unknown measurement mode"
        _ -> fail "Usage: harness <git> <repo> <mode> <target UUID> <nodes>"
