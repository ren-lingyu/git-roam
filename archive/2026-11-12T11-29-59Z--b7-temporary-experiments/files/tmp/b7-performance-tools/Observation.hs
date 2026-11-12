{-# LANGUAGE OverloadedStrings #-}

-- Opt-in application benchmark and transparent native-process counter.
module Main (main) where

import Control.Exception (IOException, finally, try)
import Control.Monad (unless)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import qualified Data.Set as Set
import GHC.Clock (getMonotonicTimeNSec)
import qualified GitRoam.Application.Check as Check
import qualified GitRoam.Application.Status as Status
import GitRoam.Git
import GitRoam.Output
import GitRoam.Protocol.Identity (parseNodeId)
import System.Environment (getArgs, getEnv, getExecutablePath, lookupEnv)
import System.Exit (exitWith)
import System.IO
import System.Process

main :: IO ()
main = do
    proxy <- lookupEnv "GIT_ROAM_BENCH_PROXY"
    args <- getArgs
    if proxy == Just "1"
        then forward args
        else case args of
            [realGit, directory, workload, selector, logPath] -> measure realGit directory workload selector logPath
            _ -> putStrLn "observation-benchmark GIT REPOSITORY WORKLOAD all|UUID COUNTER_LOG (see bench/README.org)"

-- Count actual launches separately from requests within the one scoped child.
-- The proxy adds measurable overhead; comparisons use this same proxy throughout.
forward :: [String] -> IO ()
forward args = do
    executable <- getEnv "GIT_ROAM_BENCH_GIT"
    logPath <- getEnv "GIT_ROAM_BENCH_LOG"
    BSC.appendFile logPath (BSC.pack ("process " ++ show args ++ "\n"))
    let raw = args == ["--no-replace-objects", "cat-file", "--batch"]
    withCreateProcess (proc executable args){std_in = CreatePipe} $ \input _ _ child -> case input of
        Nothing -> fail "Missing proxy input"
        Just handle -> do
            hSetBinaryMode stdin True
            hSetBinaryMode handle True
            let pump = do
                    end <- hIsEOF stdin
                    unless end $ do
                        line <- BSC.hGetLine stdin
                        if raw then BSC.appendFile logPath "request\n" else pure ()
                        BS.hPut handle (line <> "\n")
                        hFlush handle
                        pump
            -- Git may reject its input before reading all of it.
            _ <- try (pump `finally` hClose handle) :: IO (Either IOException ())
            waitForProcess child >>= exitWith

measure :: FilePath -> FilePath -> String -> String -> FilePath -> IO ()
measure realGit directory workload selector logPath = do
    self <- getExecutablePath
    calls <- newIORef (0 :: Int)
    let git = observeGit (const (modifyIORef' calls (+ 1))) $ withGitEnvironment [("GIT_ROAM_BENCH_PROXY", Just "1"), ("GIT_ROAM_BENCH_GIT", Just realGit), ("GIT_ROAM_BENCH_LOG", Just logPath)] (nativeGit self)
    selection <- if selector == "all" then pure Status.AllNodes else Status.SelectedNodes . Set.singleton <$> either fail pure (parseNodeId (BSC.pack selector))
    start <- getMonotonicTimeNSec
    (value, complete, diagnostics) <-
        if workload `elem` ["check", "check-refs"]
            then do
                result <- Check.checkManagedState git directory >>= either (fail . show) pure
                pure (checkValue (workload == "check-refs") result, Check.checkConclusion result == Check.Valid, length (Check.checkDiagnostics result))
            else do
                let query = case workload of
                        "repo" -> Status.RepositoryStatus
                        "default" -> Status.NodeStatusQuery selection Status.DefaultProperties
                        property -> Status.NodeStatusQuery selection (Status.SelectedProperties (Set.singleton (case property of "tip" -> Status.TipProperty; "remote" -> Status.RemoteProperty; "commit" -> Status.CommitProperty; "status" -> Status.StatusProperty; _ -> error "Unknown workload")))
                result <- Status.queryStatus git directory query >>= either (fail . show) pure
                pure (statusValue result, null (Status.reportDiagnostics result), length (Status.reportDiagnostics result))
    complete `seq` diagnostics `seq` pure ()
    observed <- getMonotonicTimeNSec
    -- Force encoding separately from observation (maps remain lazy until used).
    let bytes = encodeValue JsonFormat value
    size <- pure $! BS.length bytes
    finished <- getMonotonicTimeNSec
    logical <- readIORef calls
    BL.putStr . (<> "\n") $
        Aeson.encode $
            Aeson.object
                [ "observation_seconds" Aeson..= (fromIntegral (observed - start) / 1e9 :: Double)
                , "serialization_seconds" Aeson..= (fromIntegral (finished - observed) / 1e9 :: Double)
                , "output_bytes" Aeson..= size
                , "logical_observed_invocations" Aeson..= logical
                , "complete" Aeson..= complete
                , "diagnostics" Aeson..= diagnostics
                ]
