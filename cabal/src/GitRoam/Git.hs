{-# LANGUAGE RankNTypes #-}

module GitRoam.Git (
    Git (Git, runGit),
    GitInvocation (..),
    GitResult (..),
    GitError (..),
    defaultGitExecutable,
    nativeGit,
    withGitBatch,
    withGitEnvironment,
    observeGit,
) where

import Control.Concurrent.Async (concurrently)
import Control.Exception (IOException, displayException, finally, try)
import qualified Data.ByteString as BS
import GitRoam.BuildInfo (defaultGitExecutable)
import qualified GitRoam.Git.Batch as Batch
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.IO (hClose)
import System.Process (
    CreateProcess (..),
    StdStream (CreatePipe),
    proc,
    waitForProcess,
    withCreateProcess,
 )

data GitInvocation = GitInvocation
    { gitDirectory :: FilePath
    , gitArguments :: [String]
    , gitInput :: BS.ByteString
    , gitEnvironment :: [(String, Maybe String)]
    }
    deriving (Eq, Show)

data GitResult = GitResult
    { gitExitCode :: ExitCode
    , gitStdout :: BS.ByteString
    , gitStderr :: BS.ByteString
    }
    deriving (Eq, Show)

data GitError
    = InvalidGitInvocation String
    | GitTransportError String
    deriving (Eq, Show)

data Git m
    = Git
        { runGit :: GitInvocation -> m (Either GitError GitResult)
        }
    | ManagedGit
        { runGit :: GitInvocation -> m (Either GitError GitResult)
        , scopedBatch :: forall a. GitInvocation -> ((BS.ByteString -> IO (Either GitError GitResult)) -> IO a) -> IO (Either GitError a)
        }

-- These decorators preserve the native streaming capability. A bare Git
-- constructor remains a one-shot test double, with no hidden native process.
withGitEnvironment :: [(String, Maybe String)] -> Git IO -> Git IO
withGitEnvironment environment git = decorate (\invocation -> invocation{gitEnvironment = environment ++ gitEnvironment invocation}) (const (pure ())) git

observeGit :: (GitInvocation -> IO ()) -> Git IO -> Git IO
observeGit = decorate id

decorate :: (GitInvocation -> GitInvocation) -> (GitInvocation -> IO ()) -> Git IO -> Git IO
decorate transform observer git = case git of
    Git call -> Git (\invocation -> let actual = transform invocation in observer actual >> call actual)
    ManagedGit call batch ->
        ManagedGit
            (\invocation -> let actual = transform invocation in observer actual >> call actual)
            (\invocation action -> let actual = transform invocation in observer actual >> batch actual action)

-- A logical raw request still has the usual GitInvocation/Result shape; only
-- matching raw requests within this scope use the shared child. Other commands
-- retain their adapter, environment, observations and one-shot behavior.
withGitBatch :: Git IO -> GitInvocation -> (Git IO -> IO a) -> IO (Either GitError a)
withGitBatch _ invocation _
    | gitArguments invocation /= ["--no-replace-objects", "cat-file", "--batch"] || not (BS.null (gitInput invocation)) =
        pure (Left (InvalidGitInvocation "Raw session startup requires cat-file --batch with empty input"))
withGitBatch git invocation action = case git of
    Git _ -> Right <$> action git
    ManagedGit{} -> scopedBatch git invocation $ \reader -> action $ Git $ \request ->
        if gitDirectory request == gitDirectory invocation
            && gitArguments request == gitArguments invocation
            && gitEnvironment request == gitEnvironment invocation
            then reader (gitInput request)
            else runGit git request

-- Use the native argv API and binary stdio; retain ordinary Git configuration.
nativeGit :: FilePath -> Git IO
nativeGit executable = ManagedGit invokeOnce batch
  where
    batch invocation action = case validate executable invocation of
        Left problem -> pure (Left (InvalidGitInvocation problem))
        Right () -> do
            prepared <- captureIO (overriddenEnvironment (gitEnvironment invocation))
            case prepared of
                Left problem -> pure (Left (GitTransportError (displayException problem)))
                Right environment -> do
                    let command = (proc executable (gitArguments invocation)){cwd = Just (gitDirectory invocation), env = environment}
                        convert (Batch.BatchFailure message diagnostic) = GitTransportError (message ++ if BS.null diagnostic then "" else ": " ++ show diagnostic)
                    outcome <- Batch.withBatchProcess command $ \reader -> action $ \input -> do
                        result <- reader input
                        pure (either (Left . convert) (Right . (\bytes -> GitResult ExitSuccess bytes BS.empty)) result)
                    pure (either (Left . convert) Right outcome)
    invokeOnce invocation =
        case validate executable invocation of
            Left problem -> pure (Left (InvalidGitInvocation problem))
            Right () -> do
                result <- captureIO (invoke executable invocation)
                pure $ case result of
                    Left problem -> Left (GitTransportError (displayException problem))
                    Right value -> value

invoke :: FilePath -> GitInvocation -> IO (Either GitError GitResult)
invoke executable invocation = do
    environment <- overriddenEnvironment (gitEnvironment invocation)
    let command =
            (proc executable (gitArguments invocation))
                { cwd = Just (gitDirectory invocation)
                , env = environment
                , std_in = CreatePipe
                , std_out = CreatePipe
                , std_err = CreatePipe
                }
    withCreateProcess command $ \input output errors process ->
        case (input, output, errors) of
            (Just inputHandle, Just outputHandle, Just errorHandle) -> do
                ((written, code), (stdoutBytes, stderrBytes)) <-
                    concurrently
                        ( do
                            written <-
                                captureIO $
                                    BS.hPut inputHandle (gitInput invocation)
                                        `finally` hClose inputHandle
                            code <- waitForProcess process
                            pure (written, code)
                        )
                        (concurrently (BS.hGetContents outputHandle) (BS.hGetContents errorHandle))
                pure $ case written of
                    Left problem
                        | code == ExitSuccess ->
                            Left (GitTransportError (displayException problem))
                    _ -> Right (GitResult code stdoutBytes stderrBytes)
            _ -> pure (Left (GitTransportError "Git pipe creation failed"))

captureIO :: IO a -> IO (Either IOException a)
captureIO = try

overriddenEnvironment :: [(String, Maybe String)] -> IO (Maybe [(String, String)])
overriddenEnvironment [] = pure Nothing
overriddenEnvironment overrides = do
    inherited <- getEnvironment
    pure (Just (foldl replace inherited overrides))
  where
    replace environment (name, value) =
        let remaining = filter ((/= name) . fst) environment
         in case value of
                Nothing -> remaining
                Just item -> (name, item) : remaining

validate :: FilePath -> GitInvocation -> Either String ()
validate executable invocation
    | null executable = Left "Empty Git executable"
    | any (elem '\0') (executable : gitDirectory invocation : gitArguments invocation) =
        Left "NUL byte in a Git executable, directory, or argument"
    | any invalidBinding (gitEnvironment invocation) = Left "Invalid Git environment binding"
    | otherwise = Right ()
  where
    invalidBinding (name, value) =
        null name || any (`elem` name) "=\0" || maybe False (elem '\0') value
