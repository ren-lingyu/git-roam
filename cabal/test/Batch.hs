{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import BatchFixture (fixtureGit, frame, payload, runBatchFixture)
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
import System.Environment (getExecutablePath)
import System.FilePath ((</>))
import System.Posix.Signals (nullSignal, signalProcess)
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
main =
    runBatchFixture $
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
            , ("observation separates verified responses from process exit failure", observedExit)
            , ("observation classifies trailing stdout as uncertain", observedTail)
            , ("observation startup failure never runs the callback", observedStartup)
            , ("observation normal response and reader scope", observedNormal)
            , ("observation callback exceptions retain propagation", observedException)
            , ("observation cancellation still kills and reaps", observedCancellation)
            ]
                ++ [("observation retains verified prefix and poisons later requests " ++ show format, observedPrefix format) | format <- [Sha1, Sha256]]
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
    expectLeft result

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
    expectLeft result

objectErrors :: IO ()
objectErrors = withTempDirectory $ \directory -> do
    executable <- getExecutablePath
    target <- expectRight (parseObjectId Sha1 oid)
    forM_ [("missing", MissingObject), ("echo", WrongObjectType "blob")] $ \(scenario, expected) -> do
        let git = withGitEnvironment [("GIT_ROAM_BATCH_FIXTURE", Just scenario), ("GIT_ROAM_BATCH_PID", Just (directory </> "pid"))] (nativeGit executable)
        result <- withHistorySource git directory Sha1 [] $ \source -> loadCommit source target
        expectRight result >>= assertEqual (Left expected)

observedNormal :: IO ()
observedNormal = withTempDirectory $ \directory -> do
    git <- fixtureGit "echo" directory
    captured <- newIORef Nothing
    result <- withGitBatchObservation git (invocation directory "") $ \scoped -> do
        writeIORef captured (Just scoped)
        response <- readRaw scoped directory oid >>= expectRight
        pure (gitStdout response)
    assertEqual (BatchCompleted (frame oid (payload oid)) []) result
    escapedReader <- readIORef captured >>= maybe (fail "No reader captured") pure
    readRaw escapedReader directory oid >>= expectLeft
    gone (directory </> "child.pid")

observedExit :: IO ()
observedExit = withTempDirectory $ \directory -> do
    git <- fixtureGit "nonzero" directory
    result <- withGitBatchObservation git (invocation directory "") $ \scoped -> readRaw scoped directory oid >>= expectRight
    case result of
        BatchCompleted response [BatchProcessExited _] -> assertEqual (frame oid (payload oid)) (gitStdout response)
        _ -> fail (show result)
    gone (directory </> "child.pid")

observedTail :: IO ()
observedTail = withTempDirectory $ \directory -> do
    git <- fixtureGit "trailing" directory
    result <- withGitBatchObservation git (invocation directory "") $ \scoped -> readRaw scoped directory oid >>= expectRight
    case result of
        BatchCompleted response [BatchCompletionUncertain _] -> assertEqual (frame oid (payload oid)) (gitStdout response)
        _ -> fail (show result)
    gone (directory </> "child.pid")

observedPrefix :: ObjectFormat -> IO ()
observedPrefix format = withTempDirectory $ \directory -> do
    git <- fixtureGit "later-body-eof" directory
    let value = BS.replicate (objectIdLength format) 97
    result <- withGitBatchObservation git (invocation directory "") $ \scoped -> do
        first <- readRaw scoped directory value >>= expectRight
        second <- readRaw scoped directory value
        third <- readRaw scoped directory value
        expectLeft second
        expectLeft third
        pure (gitStdout first)
    case result of
        BatchCompleted response [BatchRequestFailed _] -> assertEqual (frame value (payload value)) response
        _ -> fail (show result)
    requests <- BSC.lines <$> BS.readFile (directory </> "requests")
    assertEqual [value, value] requests
    gone (directory </> "child.pid")

observedStartup :: IO ()
observedStartup = withTempDirectory $ \directory -> do
    called <- newIORef False
    result <- withGitBatchObservation (nativeGit (directory </> "absent")) (invocation directory "") (\_ -> writeIORef called True)
    case result of BatchNotStarted _ -> pure (); _ -> fail (show result)
    readIORef called >>= assertEqual False

observedException :: IO ()
observedException = withTempDirectory $ \directory -> do
    git <- fixtureGit "echo" directory
    result <-
        try
            ( withGitBatchObservation git (invocation directory "") $ \scoped -> do
                _ <- readRaw scoped directory oid >>= expectRight
                ioError (userError "observation callback exception")
            ) ::
            IO (Either IOException (BatchOutcome GitError ()))
    expectLeft result
    gone (directory </> "child.pid")

observedCancellation :: IO ()
observedCancellation = withTempDirectory $ \directory -> do
    git <- fixtureGit "hang" directory
    let pid = directory </> "child.pid"
    worker <- async (withGitBatchObservation git (invocation directory "") (\scoped -> readRaw scoped directory oid))
    _ <- timeout 2000000 (waitPid pid) >>= maybe (fail "No observation child PID") pure
    done <- timeout 5000000 (cancel worker)
    assertEqual (Just ()) done
    waitCatch worker >>= expectLeft
    gone pid

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
