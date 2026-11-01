{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Control.Exception (bracket, evaluate)
import Control.Monad (unless)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GHC.Clock (getMonotonicTimeNSec)
import GitRoam.Application.Inspect
import GitRoam.Git
import GitRoam.Protocol.Repository
import System.Environment (getArgs)
import System.Exit (ExitCode (..))
import System.Info (compilerVersion)
import Data.Version (showVersion)
import System.IO
import System.Process

data Batch = Batch Handle Handle ProcessHandle

startBatch :: FilePath -> FilePath -> IO Batch
startBatch git directory = do
    (Just input, Just output, _, process) <- createProcess (proc git ["--no-replace-objects", "cat-file", "--batch"])
        { cwd = Just directory, std_in = CreatePipe, std_out = CreatePipe, std_err = Inherit }
    hSetBinaryMode input True
    hSetBinaryMode output True
    hSetBuffering input NoBuffering
    hSetBuffering output NoBuffering
    pure (Batch input output process)

stopBatch :: Batch -> IO ()
stopBatch (Batch input output process) = do
    hClose input
    code <- waitForProcess process
    hClose output
    unless (code == ExitSuccess) (fail "Persistent batch process failed")

readExactly :: Handle -> Int -> IO BS.ByteString
readExactly handle size = go size []
  where
    go 0 chunks = pure (BS.concat (reverse chunks))
    go remaining chunks = do
        bytes <- BS.hGet handle remaining
        unless (not (BS.null bytes)) (fail "Truncated batch body")
        go (remaining - BS.length bytes) (bytes : chunks)

request :: Batch -> BS.ByteString -> IO GitResult
request (Batch input output _) bytes = do
    unless (length (BSC.lines bytes) == 1) (fail "Experiment expects one full OID per logical request")
    BS.hPut input bytes
    hFlush input
    header <- BSC.hGetLine output
    body <- case BSC.words header of
        [_, "missing"] -> pure ""
        [_, _, raw] | Just (size, "") <- BSC.readInt raw, size >= 0 -> readExactly output (size + 1)
        _ -> fail "Malformed batch response"
    pure (GitResult ExitSuccess (header <> "\n" <> body) "")

main :: IO ()
main = do
    args <- getArgs
    case args of
        [git, directory, mode] | mode `elem` ["oneshot", "persistent"] -> do
            counts <- newIORef (Map.empty :: Map.Map String Int)
            let native = nativeGit git
                run batch = do
                    let wrapped = Git $ \invocation -> do
                            let category
                                    | "--batch" `elem` gitArguments invocation = "batch"
                                    | any ("--batch-check" `BSC.isPrefixOf`) (map BSC.pack (gitArguments invocation)) = "metadata"
                                    | otherwise = "other"
                            modifyIORef' counts (Map.insertWith (+) category (1 :: Int))
                            case (batch, category) of
                                (Just process, "batch") -> Right <$> request process (gitInput invocation)
                                _ -> runGit native invocation
                    observed <- inspectState wrapped directory [] Nothing
                    report <- either (fail . show) pure observed
                    state <- either (fail . show) pure (reportManagedState report)
                    let digest = SHA256.hash (BSC.pack (show (Map.toList (managedRefs state), Map.toList (retainedCheckpoints state))))
                    _ <- evaluate (BS.length digest)
                    pure (Map.size (managedRefs state), sum (map Set.size (Map.elems (retainedCheckpoints state))), BS.concatMap hex digest)
            before <- getMonotonicTimeNSec
            (nodes, versions, digest) <- if mode == "persistent"
                then bracket (startBatch git directory) stopBatch (run . Just)
                else run Nothing
            after <- getMonotonicTimeNSec
            totals <- readIORef counts
            let count name = Map.findWithDefault 0 name totals
                physical = count "metadata" + count "other" + if mode == "persistent" then 1 else count "batch"
                elapsed = fromIntegral (after - before) / 1e9 :: Double
            putStrLn ("{\"mode\":\"" ++ mode ++ "\",\"nodes\":" ++ show nodes
                ++ ",\"checkpoints\":" ++ show versions ++ ",\"validator_seconds\":" ++ show elapsed
                ++ ",\"logical_batch_requests\":" ++ show (count "batch")
                ++ ",\"metadata_processes\":" ++ show (count "metadata")
                ++ ",\"other_processes\":" ++ show (count "other")
                ++ ",\"physical_git_processes\":" ++ show physical
                ++ ",\"result_digest\":\"" ++ BSC.unpack digest
                ++ "\",\"ghc\":\"" ++ showVersion compilerVersion ++ "\"}")
        _ -> fail "Usage: reader-harness <git> <repository> <oneshot|persistent>"
  where
    hex byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48 + n else 87 + n
