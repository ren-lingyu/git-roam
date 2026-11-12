{-# LANGUAGE OverloadedStrings #-}

module BatchFixture (runBatchFixture, fixtureGit, payload, frame) where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.List (isPrefixOf)
import GitRoam.Git
import System.Directory (getCurrentDirectory)
import System.Environment (getArgs, getEnv, getEnvironment, getExecutablePath, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO
import System.Posix.Process (getProcessID)
import System.Posix.Signals (Handler (Ignore), installHandler, sigTERM)

-- The test executable is a real scoped child; ordinary Git commands delegate
-- to the pinned native executable, while batch faults are controlled here.
runBatchFixture :: IO () -> IO ()
runBatchFixture tests = do
    args <- getArgs
    scenario <- lookupEnv "GIT_ROAM_BATCH_FIXTURE"
    case scenario of
        Nothing -> tests
        Just _ | args == ["--no-replace-objects", "cat-file", "--batch"] -> fake
        Just _ -> do
            directory <- getCurrentDirectory
            bytes <- BS.hGetContents stdin
            result <- runGit (nativeGit defaultGitExecutable) (GitInvocation directory args bytes [])
            case result of
                Left problem -> hPrint stderr problem >> exitWith (ExitFailure 128)
                Right value -> do
                    BS.hPut stdout (gitStdout value)
                    BS.hPut stderr (gitStderr value)
                    exitWith (gitExitCode value)

fixtureGit :: String -> FilePath -> IO (Git IO)
fixtureGit scenario directory = do
    executable <- getExecutablePath
    inherited <- getEnvironment
    writeFile (directory </> "requests") ""
    writeFile (directory </> "requests.starts") ""
    let environment = [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name] ++ [("GIT_CONFIG_NOSYSTEM", Just "1"), ("GIT_CONFIG_GLOBAL", Just "/dev/null"), ("GIT_ROAM_BATCH_FIXTURE", Just scenario), ("GIT_ROAM_BATCH_PID", Just (directory </> "child.pid")), ("GIT_ROAM_BATCH_REQUESTS", Just (directory </> "requests"))]
    pure (withGitEnvironment environment (nativeGit executable))

payload :: BS.ByteString -> BS.ByteString
payload value = value <> BS.pack [0, 10, 255, 13, 0]

frame :: BS.ByteString -> BS.ByteString -> BS.ByteString
frame value body = value <> " blob " <> BSC.pack (show (BS.length body)) <> "\n" <> body <> "\n"

fake :: IO ()
fake = do
    scenario <- getEnv "GIT_ROAM_BATCH_FIXTURE"
    file <- getEnv "GIT_ROAM_BATCH_PID"
    when (scenario `elem` ["hang", "shutdown"]) $ do
        _ <- installHandler sigTERM Ignore Nothing
        pure ()
    pid <- getProcessID
    writeFile file (show pid)
    requests <- lookupEnv "GIT_ROAM_BATCH_REQUESTS"
    maybe (pure ()) (\path -> appendFile (path ++ ".starts") "start\n") requests
    when (scenario == "early-exit") (exitWith (ExitFailure 7))
    mapM_ (\h -> hSetBinaryMode h True >> hSetBuffering h NoBuffering) [stdin, stdout, stderr]
    let loop n = do
            eof <- hIsEOF stdin
            if eof
                then do
                    when (scenario `elem` ["trailing", "commit-trailing"]) (BS.hPut stdout "unexpected")
                    when (scenario == "shutdown") foreverWait
                    when (scenario == "commit-nonzero") (exitWith (ExitFailure 7))
                else do
                    value <- BSC.getLine
                    maybe (pure ()) (\path -> BS.appendFile path (value <> "\n")) requests
                    case scenario of
                        "hang" -> foreverWait
                        "bad-oid" -> BS.hPut stdout (frame (BS.replicate (BS.length value) 98) "wrong")
                        "bad-size" -> BS.hPut stdout (value <> " blob not-a-size\n")
                        "bad-whitespace" -> BS.hPut stdout (value <> "  blob 0\n\n")
                        "overflow" -> BS.hPut stdout (value <> " blob 999999999999999999999999999999\n")
                        "header-eof" -> BS.hPut stdout (value <> " blob") >> exitWith ExitSuccess
                        "body-eof" -> BS.hPut stdout (value <> " blob 100\nshort") >> exitWith ExitSuccess
                        "bad-terminator" -> BS.hPut stdout (value <> " blob 1\nx!")
                        "oversized-header" -> BS.hPut stdout (BS.replicate 4096 97)
                        "unknown-type" -> BS.hPut stdout (value <> " invalid 0\n\n")
                        "missing" | value == BS.replicate 40 97 -> BS.hPut stdout (value <> " missing\n")
                        "large" -> BS.hPut stdout (frame value (BS.replicate 131073 255 <> payload value))
                        "stderr" -> do
                            BS.hPut stderr ("fixture diagnostic\n" <> BS.replicate 262144 120)
                            BS.hPut stdout (frame value (payload value))
                            hFlush stdout
                            exitWith (ExitFailure 7)
                        "nonzero" -> BS.hPut stdout (frame value (payload value)) >> hFlush stdout >> exitWith (ExitFailure 7)
                        "later-body-eof" | n == 2 -> BS.hPut stdout (value <> " blob 100\nshort") >> exitWith ExitSuccess
                        "commit-truncated" | n == 2 -> BS.hPut stdout (value <> " commit 100\nshort") >> exitWith ExitSuccess
                        "commit-bad-oid" | n == 2 -> BS.hPut stdout (BS.replicate (BS.length value) 97 <> " commit 0\n\n")
                        "commit-bad-size" | n == 2 -> BS.hPut stdout (value <> " commit invalid\n")
                        "commit-bad-terminator" | n == 2 -> BS.hPut stdout (value <> " commit 1\nx!")
                        "commit-missing" | n == 2 -> BS.hPut stdout (value <> " missing\n")
                        _ | "commit-" `isPrefixOf` scenario -> do
                            directory <- getCurrentDirectory
                            result <- runGit (nativeGit defaultGitExecutable) (GitInvocation directory ["--no-replace-objects", "cat-file", "--batch"] (value <> "\n") [])
                            case result of
                                Right response | gitExitCode response == ExitSuccess -> BS.hPut stdout (gitStdout response)
                                _ -> hPrint stderr result >> exitWith (ExitFailure 128)
                            when (scenario == "commit-first-exit") (hFlush stdout >> exitWith (ExitFailure 7))
                        _ -> BS.hPut stdout (frame value (payload value))
                    hFlush stdout
                    loop (n + 1)
    loop (1 :: Int)
  where
    foreverWait = threadDelay 10000000 >> foreverWait
