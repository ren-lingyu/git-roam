module GitRoam.Git (
    Git (..),
    GitInvocation (..),
    GitResult (..),
    GitError (..),
    defaultGitExecutable,
    nativeGit,
) where

import Control.Concurrent.Async (concurrently)
import Control.Exception (IOException, displayException, finally, try)
import qualified Data.ByteString as BS
import GitRoam.BuildInfo (defaultGitExecutable)
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

newtype Git m = Git
    { runGit :: GitInvocation -> m (Either GitError GitResult)
    }

-- Use the native argv API and binary stdio; retain ordinary Git configuration.
nativeGit :: FilePath -> Git IO
nativeGit executable = Git $ \invocation ->
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
