{-# LANGUAGE OverloadedStrings #-}

-- Raw transport only. Object decoding and knowledge interpretation live above it.
module GitRoam.Git.Batch (BatchFailure (..), withBatchProcess) where

import Control.Concurrent (ThreadId, myThreadId, throwTo)
import Control.Concurrent.Async (Async, async, cancel, waitCatch)
import Control.Concurrent.MVar
import Control.Exception (AsyncException (ThreadKilled), Exception, IOException, SomeException, displayException, finally, fromException, mask, onException, throwIO, try, uninterruptibleMask_)
import Control.Monad (forM_, unless, when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import GitRoam.ObjectId
import System.Exit (ExitCode (..))
import System.IO
import System.Posix.Signals (sigKILL, sigTERM, signalProcessGroup)
import System.Process
import System.Timeout (timeout)

data BatchFailure = BatchFailure String BS.ByteString deriving (Eq, Show)
data CleanupException = CleanupException String BatchFailure deriving (Show)
instance Exception CleanupException

data Session = Session
    { input :: Handle
    , output :: Handle
    , errors :: Handle
    , process :: ProcessHandle
    , gate :: MVar ()
    , closed :: IORef Bool
    , poisoned :: IORef Bool
    , buffered :: IORef BS.ByteString
    , diagnostics :: IORef BS.ByteString
    , truncated :: IORef Bool
    , drainer :: Async ()
    , active :: IORef (Maybe ThreadId)
    }

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

tryAny :: IO a -> IO (Either SomeException a)
tryAny = try

-- Acquisition is masked; callbacks and requests remain interruptible. Escaping
-- callbacks are unsupported, but escaped readers fail closed after the scope.
withBatchProcess :: CreateProcess -> ((BS.ByteString -> IO (Either BatchFailure BS.ByteString)) -> IO a) -> IO (Either BatchFailure a)
withBatchProcess command action = mask $ \restore -> do
    acquired <- tryIO (acquire command)
    case acquired of
        Left problem -> pure (Left (BatchFailure ("Cannot start raw Git session: " ++ displayException problem) ""))
        Right session -> do
            outcome <- tryAny (restore (action (request session)))
            worker <- async (finishSafely session (either (const True) (const False) outcome))
            -- The separate cleanup worker retains interruptible waits/timeouts;
            -- repeated cancellation cannot abandon cleanup in the owner thread.
            finished <- uninterruptibleMask_ (waitCatch worker)
            cleanup <- case finished of
                Right value -> pure value
                Left problem -> pure (Left (BatchFailure ("Raw Git cleanup worker failed: " ++ displayException problem) ""))
            case outcome of
                Left problem -> case cleanup of
                    Right () -> throwIO problem
                    Left failure -> throwIO (CleanupException (displayException problem) failure)
                Right value -> pure (value <$ cleanup)

finishSafely :: Session -> Bool -> IO (Either BatchFailure ())
finishSafely session interrupted = do
    result <- tryAny (finish session interrupted)
    case result of
        Right value -> pure value
        Left problem -> do
            writeIORef (closed session) True
            activeThread <- readIORef (active session)
            forM_ activeThread $ \thread -> do
                _ <- timeout 500000 (throwTo thread ThreadKilled)
                pure ()
            _ <- tryAny (stop (process session))
            _ <- tryAny (cancel (drainer session))
            _ <- mapM (tryIO . hClose) [input session, output session, errors session]
            _ <- tryPutMVar (gate session) ()
            pure (Left (BatchFailure ("Raw Git cleanup failed: " ++ displayException problem) ""))

acquire :: CreateProcess -> IO Session
acquire command = do
    handles@(stdinPipe, stdoutPipe, stderrPipe, child) <-
        createProcess
            command
                { std_in = CreatePipe
                , std_out = CreatePipe
                , std_err = CreatePipe
                , create_group = True
                }
    let setup = case (stdinPipe, stdoutPipe, stderrPipe) of
            (Just inHandle, Just outHandle, Just errHandle) -> do
                mapM_ (\h -> hSetBinaryMode h True >> hSetBuffering h NoBuffering) [inHandle, outHandle, errHandle]
                lock <- newMVar ()
                isClosed <- newIORef False
                isPoisoned <- newIORef False
                pending <- newIORef ""
                diagnostic <- newIORef ""
                wasTruncated <- newIORef False
                activeThread <- newIORef Nothing
                worker <- async (drain errHandle diagnostic wasTruncated)
                pure (Session inHandle outHandle errHandle child lock isClosed isPoisoned pending diagnostic wasTruncated worker activeThread)
            _ -> ioError (userError "Raw Git session pipes were not created")
    setup `onException` abortAcquisition handles

abortAcquisition :: (Maybe Handle, Maybe Handle, Maybe Handle, ProcessHandle) -> IO ()
abortAcquisition (a, b, c, child) = do
    stopped <- stop child
    results <- mapM (tryIO . hClose) [h | Just h <- [a, b, c]]
    unless (null stopped && all (either (const False) (const True)) results) $
        ioError (userError "Failed to clean up raw Git session acquisition")

-- Keep at most 8 KiB, while continuously consuming all stderr bytes.
drain :: Handle -> IORef BS.ByteString -> IORef Bool -> IO ()
drain handle prefix overflow = do
    bytes <- BS.hGetSome handle 65536
    unless (BS.null bytes) $ do
        saved <- readIORef prefix
        let available = 8192 - BS.length saved
        writeIORef prefix (saved <> BS.take available bytes)
        when (BS.length bytes > available) (writeIORef overflow True)
        drain handle prefix overflow

request :: Session -> BS.ByteString -> IO (Either BatchFailure BS.ByteString)
request session bytes = case requestOid bytes of
    Left problem -> pure (Left (BatchFailure problem ""))
    Right oid -> withMVar (gate session) $ \_ -> mask $ \restore -> do
        unavailable <- (||) <$> readIORef (closed session) <*> readIORef (poisoned session)
        if unavailable
            then pure (Left (BatchFailure "Raw Git session is closed or unusable" ""))
            else do
                thread <- myThreadId
                writeIORef (active session) (Just thread)
                result <- tryAny (restore (exchange session oid)) `finally` writeIORef (active session) Nothing
                case (result :: Either SomeException BS.ByteString) of
                    Right frame -> pure (Right frame)
                    Left problem -> do
                        writeIORef (poisoned session) True
                        case fromException problem :: Maybe IOException of
                            Nothing -> throwIO problem
                            Just failure -> do
                                diagnostic <- savedDiagnostics session
                                pure (Left (BatchFailure (displayException failure) diagnostic))

requestOid :: BS.ByteString -> Either String BS.ByteString
requestOid bytes = do
    oid <- maybe (Left "Expected exactly one newline-terminated full object OID") Right (BS.stripSuffix "\n" bytes)
    format <- case BS.length oid of
        40 -> Right Sha1
        64 -> Right Sha256
        _ -> Left "Raw session requires a full object OID"
    _ <- parseObjectId format oid
    pure oid

exchange :: Session -> BS.ByteString -> IO BS.ByteString
exchange session oid = do
    BS.hPut (input session) (oid <> "\n")
    hFlush (input session)
    header <- headerLine session
    if header == oid <> " missing"
        then pure (header <> "\n")
        else do
            size <- case BSC.words header of
                [actual, kind, raw]
                    | actual == oid && kind `elem` ["commit", "tree", "blob", "tag"]
                    , header == oid <> " " <> kind <> " " <> raw
                    , not (BS.null raw) && BS.all (\n -> n >= 48 && n <= 57) raw
                    , Just (count, "") <- BSC.readInteger raw
                    , count <= toInteger (maxBound :: Int) - 1 ->
                        pure (fromInteger count)
                _ -> ioError (userError "Malformed raw Git batch header, size, type or response OID")
            body <- exact session size
            separator <- exact session 1
            unless (separator == "\n") (ioError (userError "Raw Git batch response has no body terminator"))
            pure (header <> "\n" <> body <> separator)

-- Bound header memory even when a faulty executable never emits a newline.
headerLine :: Session -> IO BS.ByteString
headerLine session = do
    bytes <- readIORef (buffered session)
    case BSC.break (== '\n') bytes of
        (line, rest) | not (BS.null rest) -> do
            when (BS.length line > 256) (ioError (userError "Oversized raw Git batch header"))
            writeIORef (buffered session) (BS.drop 1 rest)
            pure (BS.copy line)
        _ -> do
            when (BS.length bytes > 256) (ioError (userError "Oversized raw Git batch header"))
            chunk <- BS.hGetSome (output session) 4096
            when (BS.null chunk) (ioError (userError "Truncated raw Git batch header"))
            writeIORef (buffered session) (bytes <> chunk)
            headerLine session

exact :: Session -> Int -> IO BS.ByteString
exact session count = do
    bytes <- readIORef (buffered session)
    let (first, rest) = BS.splitAt count bytes
    writeIORef (buffered session) rest
    go (count - BS.length first) [first]
  where
    go 0 chunks = pure (BS.concat (reverse chunks))
    go remaining chunks = do
        chunk <- BS.hGet (output session) (min 65536 remaining)
        when (BS.null chunk) (ioError (userError "Truncated raw Git batch object body"))
        go (remaining - BS.length chunk) (chunk : chunks)

savedDiagnostics :: Session -> IO BS.ByteString
savedDiagnostics session = do
    prefix <- readIORef (diagnostics session)
    overflow <- readIORef (truncated session)
    pure (prefix <> if overflow then "\n[stderr truncated]" else "")

-- SIGKILL escalation is confined to our own newly created process group.
stop :: ProcessHandle -> IO [String]
stop child = do
    status <- getProcessExitCode child
    case status of
        Just _ -> pure []
        Nothing -> do
            let signal sig = do
                    pid <- getPid child
                    case pid of
                        Nothing -> pure ()
                        Just value -> do
                            result <- tryIO (signalProcessGroup sig value)
                            case result of
                                Right () -> pure ()
                                Left _ -> terminateProcess child
            _ <- tryIO (signal sigTERM)
            exited <- timeout 500000 (waitForProcess child)
            case exited of
                Just _ -> pure []
                Nothing -> do
                    killed <- tryIO (signal sigKILL)
                    reaped <- timeout 2000000 (waitForProcess child)
                    pure (["Cannot kill raw Git process group" | either (const True) (const False) killed] ++ ["Cannot reap raw Git child" | reaped == Nothing])

finish :: Session -> Bool -> IO (Either BatchFailure ())
finish session interrupted = do
    writeIORef (closed session) True
    idle <- tryTakeMVar (gate session)
    broken <- readIORef (poisoned session)
    let abnormal = interrupted || broken || idle == Nothing
    escaped <- readIORef (active session)
    forM_ escaped $ \thread -> do
        _ <- timeout 500000 (throwTo thread ThreadKilled)
        pure ()
    killed <- if abnormal then stop (process session) else pure []
    inputResult <- tryIO (hClose (input session))
    -- Drain unexpected stdout too, so shutdown cannot deadlock on a full pipe.
    tailBytes <- newIORef ""
    tailOverflow <- newIORef False
    pending <- readIORef (buffered session)
    let drainTail = drain (output session) tailBytes tailOverflow
    tailWorker <- if idle == Nothing then pure Nothing else Just <$> async drainTail
    outcome <-
        ( timeout 2000000 $ do
            code <- waitForProcess (process session)
            stderrResult <- waitCatch (drainer session)
            stdoutResult <- maybe (pure (Right ())) waitCatch tailWorker
            pure (code, stderrResult, stdoutResult)
        )
            `onException` mapM_ cancel tailWorker
    forced <-
        ( case outcome of
            Nothing -> stop (process session)
            Just _ -> pure []
        )
            `onException` mapM_ cancel tailWorker
    cancel (drainer session)
    mapM_ cancel tailWorker
    handles <- mapM (tryIO . hClose) [input session, output session, errors session]
    diagnostic <- savedDiagnostics session
    tailData <- readIORef tailBytes
    let closeErrors =
            ["Raw Git input close failed: " ++ displayException problem | Left problem <- [inputResult], not abnormal]
                ++ ["Raw Git handle close failed: " ++ displayException problem | Left problem <- handles]
        completion = case outcome of
            Nothing -> ["Raw Git shutdown timed out"]
            Just (code, err, out) ->
                ["Raw Git exited unsuccessfully: " ++ show code | code /= ExitSuccess && not abnormal]
                    ++ ["Raw Git stderr drain failed: " ++ displayException problem | Left problem <- [err]]
                    ++ ["Raw Git stdout drain failed: " ++ displayException problem | Left problem <- [out]]
        problems =
            killed
                ++ forced
                ++ closeErrors
                ++ completion
                ++ ["Raw Git request outlived its session scope" | idle == Nothing]
                ++ ["Unexpected trailing raw Git stdout" | not abnormal && not (BS.null pending && BS.null tailData)]
    when (idle /= Nothing) (putMVar (gate session) ())
    pure $ if null problems then Right () else Left (BatchFailure (unlines problems) diagnostic)
