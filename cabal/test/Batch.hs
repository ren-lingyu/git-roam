{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async
import Control.Exception (IOException, try)
import Control.Monad (forM_, when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import Data.List (isInfixOf)
import GitRoam.Application.Inspect
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.ObjectId
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import System.Environment (getArgs, getEnv, getExecutablePath)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO
import System.Posix.Process (getProcessID)
import System.Posix.Signals (Handler (Ignore), installHandler, nullSignal, sigTERM, signalProcess)
import System.Timeout (timeout)
import TestSupport
import WorktreeFixture

oid :: BS.ByteString
oid = BS.replicate 40 97

invocation :: FilePath -> BS.ByteString -> GitInvocation
invocation directory bytes = GitInvocation directory ["--no-replace-objects", "cat-file", "--batch"] bytes readOnlyEnvironment

session :: String -> (Git IO -> FilePath -> FilePath -> IO a) -> IO (Either GitError a)
session scenario action = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    let pid = directory </> "child.pid"
        git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just scenario), ("GIT_ROAM_BATCH_PID", Just pid)] (nativeGit executable)
    withGitBatch git (invocation directory "") (\scoped -> action scoped directory pid)

readRaw :: Git IO -> FilePath -> BS.ByteString -> IO (Either GitError GitResult)
readRaw git directory value = runGit git (invocation directory (value <> "\n"))

gone :: FilePath -> IO ()
gone file = do
    pid <- read <$> readFile file
    result <- try (signalProcess nullSignal pid) :: IO (Either IOException ())
    expectLeft result

main :: IO ()
main = do
    args <- getArgs
    if args == ["--no-replace-objects", "cat-file", "--batch"]
        then fake
        else
            runTests $
                [ ("one session serves binary SHA-1/SHA-256 requests", sequential)
                , ("binary bodies span pipe and chunk boundaries", largeBody)
                , ("concurrent requests keep each response paired", concurrent)
                , ("missing objects do not poison the next response", missing)
                , ("invalid requests do not enter or desynchronize the stream", invalidInput)
                , ("escaped raw reader fails after close", escaped)
                , ("process failure after a valid reply refuses success", nonzero)
                , ("stderr flood drains with bounded diagnostics", stderrFlood)
                , ("trailing stdout is a cleanup failure", trailing)
                , ("startup failure propagates", startup)
                , ("callback exception propagates after cleanup", callbackFailure)
                , ("cancellation kills and reaps a child ignoring TERM", cancellation)
                , ("repeated cancellation cannot abandon cleanup", repeatedCancellation)
                , ("outstanding request at scope end refuses and reaps", outstanding)
                , ("child exiting before input reports transport failure", earlyExit)
                , ("nonterminating shutdown refuses and reaps", shutdown)
                , ("source preserves missing and wrong-type diagnostics", objectErrors)
                ]
                    ++ [("malformed response poisons session: " ++ scenario, malformed scenario) | scenario <- ["bad-oid", "bad-size", "overflow", "header-eof", "body-eof", "bad-terminator", "oversized-header", "unknown-type", "bad-whitespace"]]
                    ++ [("full shared validators use one object process " ++ backend ++ " " ++ show format, fixture backend format real) | backend <- ["files", "reftable"], format <- [Sha1, Sha256]]

sequential :: IO ()
sequential = do
    result <- session "echo" $ \git directory _ -> forM_ [oid, BS.replicate 64 98, oid] $ \value -> do
        response <- readRaw git directory value >>= expectRight
        assertEqual (frame value (payload value)) (gitStdout response)
    _ <- expectRight result
    pure ()

largeBody :: IO ()
largeBody = do
    result <- session "large" $ \git directory _ -> do
        response <- readRaw git directory oid >>= expectRight
        assertEqual (frame oid (BS.replicate 131073 255 <> payload oid)) (gitStdout response)
    _ <- expectRight result
    pure ()

concurrent :: IO ()
concurrent = do
    result <- session "echo" $ \git directory _ ->
        mapConcurrently_
            ( \n -> do
                let value = BS.replicate 40 n
                response <- readRaw git directory value >>= expectRight
                assertEqual (frame value (payload value)) (gitStdout response)
            )
            (take 30 (cycle [97 .. 102]))
    _ <- expectRight result
    pure ()

missing :: IO ()
missing = do
    result <- session "missing" $ \git directory _ -> do
        response <- readRaw git directory oid >>= expectRight
        assertEqual (oid <> " missing\n") (gitStdout response)
        next <- readRaw git directory (BS.replicate 40 98) >>= expectRight
        assertEqual (frame (BS.replicate 40 98) (payload (BS.replicate 40 98))) (gitStdout next)
    _ <- expectRight result
    pure ()

invalidInput :: IO ()
invalidInput = do
    result <- session "echo" $ \git directory _ -> do
        forM_ ["abc\n", oid <> "\n" <> oid <> "\n", BS.replicate 40 48 <> "\n", oid <> "\0\n"] $ \bytes -> runGit git (invocation directory bytes) >>= expectLeft
        _ <- readRaw git directory oid >>= expectRight
        pure ()
    _ <- expectRight result
    pure ()

escaped :: IO ()
escaped = do
    captured <- newIORef Nothing
    result <- session "echo" $ \git directory _ -> writeIORef captured (Just (git, directory))
    _ <- expectRight result
    value <- readIORef captured
    case value of
        Just (git, directory) -> do
            response <- timeout 1000000 (readRaw git directory oid) >>= maybe (fail "Escaped reader blocked") pure
            expectLeft response
        Nothing -> fail "No reader captured"

malformed :: String -> IO ()
malformed scenario = do
    result <- session scenario $ \git directory _ -> do
        readRaw git directory oid >>= expectLeft
        readRaw git directory oid >>= expectLeft
    _ <- expectRight result
    pure ()

nonzero :: IO ()
nonzero = session "nonzero" (\git directory _ -> readRaw git directory oid >>= expectRight >> pure ()) >>= expectLeft

stderrFlood :: IO ()
stderrFlood = do
    result <- session "stderr" (\git directory _ -> readRaw git directory oid >>= expectRight >> pure ())
    case result of
        Left problem -> do
            let text = show problem
            assertTrue "Stderr failure lost diagnostic prefix" ("fixture diagnostic" `isInfixOf` text)
            assertTrue "Stderr retained unbounded data" (length text < 12000)
        Right _ -> fail "Nonzero exit reported success"

trailing :: IO ()
trailing = session "trailing" (\git directory _ -> readRaw git directory oid >>= expectRight >> pure ()) >>= expectLeft

startup :: IO ()
startup = withTempDirectory $ \directory -> do
    result <- withGitBatch (nativeGit (directory </> "missing")) (invocation directory "") (const (pure ()))
    expectLeft result
    result2 <- withGitBatch (nativeGit defaultGitExecutable) (invocation (directory </> "absent") "") (const (pure ()))
    expectLeft result2

callbackFailure :: IO ()
callbackFailure = do
    result <-
        try
            ( session
                "echo"
                ( \git directory _ -> do
                    _ <- readRaw git directory oid >>= expectRight
                    ioError (userError "fixture callback failure")
                )
            ) ::
            IO (Either IOException (Either GitError ()))
    expectLeft result

waitPid :: FilePath -> IO ()
waitPid file = do
    found <- try (readFile file >>= \bytes -> length bytes `seq` pure ()) :: IO (Either IOException ())
    case found of
        Right () -> pure ()
        Left _ -> threadDelay 10000 >> waitPid file

cancellation :: IO ()
cancellation = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    let pid = directory </> "child.pid"
        git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just "hang"), ("GIT_ROAM_BATCH_PID", Just pid)] (nativeGit executable)
    worker <- async (withGitBatch git (invocation directory "") (\scoped -> readRaw scoped directory oid))
    _ <- timeout 2000000 (waitPid pid) >>= maybe (fail "No child PID") pure
    done <- timeout 5000000 (cancel worker)
    assertEqual (Just ()) done
    waitCatch worker >>= expectLeft
    gone pid

shutdown :: IO ()
shutdown = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    let pid = directory </> "child.pid"
        git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just "shutdown"), ("GIT_ROAM_BATCH_PID", Just pid)] (nativeGit executable)
    result <- timeout 5000000 (withGitBatch git (invocation directory "") (\scoped -> readRaw scoped directory oid >>= expectRight >> pure ()))
    value <- maybe (fail "Shutdown did not finish") pure result
    expectLeft value
    gone pid

repeatedCancellation :: IO ()
repeatedCancellation = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    let pid = directory </> "child.pid"
        git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just "hang"), ("GIT_ROAM_BATCH_PID", Just pid)] (nativeGit executable)
    worker <- async (withGitBatch git (invocation directory "") (\scoped -> readRaw scoped directory oid))
    _ <- timeout 2000000 (waitPid pid) >>= maybe (fail "No child PID") pure
    done <- timeout 5000000 (concurrently_ (cancel worker) (threadDelay 50000 >> cancel worker))
    assertEqual (Just ()) done
    waitCatch worker >>= expectLeft
    gone pid

outstanding :: IO ()
outstanding = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    let pid = directory </> "child.pid"
        git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just "hang"), ("GIT_ROAM_BATCH_PID", Just pid)] (nativeGit executable)
    child <- newIORef Nothing
    result <- timeout 5000000 $ withGitBatch git (invocation directory "") $ \scoped -> do
        reader <- async (readRaw scoped directory oid)
        writeIORef child (Just reader)
        _ <- timeout 2000000 (waitPid pid) >>= maybe (fail "No child PID") pure
        threadDelay 100000
    value <- maybe (fail "Outstanding request prevented shutdown") pure result
    expectLeft value
    observed <- readIORef child
    case observed of
        Just reader -> waitCatch reader >>= expectLeft
        Nothing -> fail "No outstanding request"
    gone pid

earlyExit :: IO ()
earlyExit = do
    result <- session "early-exit" $ \git directory pid -> do
        _ <- timeout 2000000 (waitPid pid) >>= maybe (fail "No child PID") pure
        threadDelay 50000
        readRaw git directory oid >>= expectLeft
    _ <- expectRight result
    pure ()

objectErrors :: IO ()
objectErrors = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    target <- expectRight (parseObjectId Sha1 oid)
    forM_ [("missing", MissingObject), ("echo", WrongObjectType "blob")] $ \(scenario, expected) -> do
        let git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just scenario), ("GIT_ROAM_BATCH_PID", Just (directory </> "pid"))] (nativeGit executable)
        result <- withHistorySource git directory Sha1 [] $ \source -> loadCommit source target
        expectRight result >>= assertEqual (Left expected)

real :: Git IO -> FilePath -> FilePath -> FilePath -> IO ()
real git _ directory _ = do
    root git directory nodeA
    root git directory nodeB
    launched <- newIORef (0 :: Int)
    let observed = observeGit (\call -> when ("--batch" `elem` gitArguments call) (atomicModifyIORef' launched (\n -> (n + 1, ())))) git
    report <- inspectState observed directory [] Nothing >>= expectRight
    state <- expectRight (reportManagedState report)
    readIORef launched >>= assertEqual 1
    writeIORef launched 0
    candidate <- validateCandidate observed directory (managedRefs state) >>= expectRight
    assertEqual (managedRefs state) (managedRefs candidate)
    readIORef launched >>= assertEqual 1

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
    when (scenario == "early-exit") (exitWith (ExitFailure 7))
    mapM_ (\h -> hSetBinaryMode h True >> hSetBuffering h NoBuffering) [stdin, stdout, stderr]
    let loop = do
            eof <- hIsEOF stdin
            if eof
                then when (scenario == "trailing") (BS.hPut stdout "unexpected") >> when (scenario == "shutdown") foreverWait
                else do
                    value <- BSC.getLine
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
                        "missing" | value == oid -> BS.hPut stdout (value <> " missing\n")
                        "large" -> BS.hPut stdout (frame value (BS.replicate 131073 255 <> payload value))
                        "stderr" -> do
                            BS.hPut stderr ("fixture diagnostic\n" <> BS.replicate 262144 120)
                            BS.hPut stdout (frame value (payload value))
                            hFlush stdout
                            exitWith (ExitFailure 7)
                        "nonzero" -> BS.hPut stdout (frame value (payload value)) >> hFlush stdout >> exitWith (ExitFailure 7)
                        _ -> BS.hPut stdout (frame value (payload value))
                    hFlush stdout
                    loop
    loop
  where
    foreverWait = threadDelay 10000000 >> foreverWait
