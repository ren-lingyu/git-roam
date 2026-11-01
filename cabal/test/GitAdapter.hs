{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.ByteString as BS
import Data.List (isPrefixOf)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Repository
import System.Directory (createDirectory, doesFileExist, findExecutable, makeAbsolute)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process (readProcessWithExitCode)
import TestSupport

fixtureEnvironment :: IO [(String, Maybe String)]
fixtureEnvironment = do
    inherited <- getEnvironment
    pure $
        [(name, Nothing) | (name, _) <- inherited, "GIT_" `isPrefixOf` name]
            ++ [ ("GIT_CONFIG_NOSYSTEM", Just "1")
               , ("GIT_CONFIG_GLOBAL", Just "/dev/null")
               , ("GIT_AUTHOR_NAME", Just "Git Roam Fixture")
               , ("GIT_AUTHOR_EMAIL", Just "fixture@example.invalid")
               , ("GIT_COMMITTER_NAME", Just "Git Roam Fixture")
               , ("GIT_COMMITTER_EMAIL", Just "fixture@example.invalid")
               , ("GIT_AUTHOR_DATE", Just "2000-01-01T00:00:00+0000")
               , ("GIT_COMMITTER_DATE", Just "2000-01-01T00:00:00+0000")
               , ("GIT_TERMINAL_PROMPT", Just "0")
               , ("GIT_ALLOW_PROTOCOL", Just "file")
               ]

invoke ::
    [(String, Maybe String)] ->
    FilePath ->
    [String] ->
    BS.ByteString ->
    IO GitResult
invoke environment directory arguments input = do
    outcome <-
        runGit (nativeGit defaultGitExecutable) $
            GitInvocation directory arguments input environment
    expectRight outcome

success :: [(String, Maybe String)] -> FilePath -> [String] -> BS.ByteString -> IO BS.ByteString
success environment directory arguments input = do
    result <- invoke environment directory arguments input
    assertEqual ExitSuccess (gitExitCode result)
    pure (gitStdout result)

bytes :: String -> BS.ByteString
bytes = Encoding.encodeUtf8 . Text.pack

stripLf :: BS.ByteString -> BS.ByteString
stripLf = BS.takeWhile (/= 10)

main :: IO ()
main = do
    environment <- fixtureEnvironment
    runTests $
        [ ("CLI executable entry points", cliTest)
        , ("literal argv and Git configuration", argvTest environment)
        , ("binary input and large output", pipeTest environment)
        , ("Git failure status and stderr", failureTest environment)
        , ("spawn failure is distinct", spawnTest)
        , ("invalid transport inputs reject", invalidInvocationTest)
        , ("non-repository diagnostic", nonRepositoryTest environment)
        ]
            ++ [ ("repository discovery " ++ show format, repositoryTest environment format)
               | format <- [Sha1, Sha256]
               ]

cliTest :: IO ()
cliTest = do
    -- Cabal's internal build-tool dependency supplies the candidate executable.
    candidate <-
        findExecutable "git-roam"
            >>= maybe
                (ioError (userError "Cabal did not expose the candidate git-roam"))
                makeAbsolute
    (code, output, errors) <- readProcessWithExitCode candidate ["--version"] ""
    assertEqual ExitSuccess code
    assertEqual "git-roam 0.1.0\n" output
    assertEqual "" errors
    (helpCode, helpOutput, helpErrors) <- readProcessWithExitCode candidate ["help", "version"] ""
    assertEqual ExitSuccess helpCode
    assertTrue "Missing command help" ("usage: git roam version" `isPrefixOf` helpOutput)
    assertEqual "" helpErrors
    (badCode, badOutput, badErrors) <- readProcessWithExitCode candidate ["unknown"] ""
    assertEqual (ExitFailure 2) badCode
    assertEqual "" badOutput
    assertTrue "Missing error" ("git-roam: " `isPrefixOf` badErrors)

argvTest :: [(String, Maybe String)] -> IO ()
argvTest environment = withTempDirectory $ \directory -> do
    _ <- success environment directory ["init", "-q", "--initial-branch=main", "--object-format=sha1"] BS.empty
    let sentinel = directory </> "must-not-exist"
        literal = "$(touch " ++ sentinel ++ "); text with spaces\nand a newline"
    _ <- success environment directory ["config", "test.literal", literal] BS.empty
    actual <- success environment directory ["config", "--get", "test.literal"] BS.empty
    assertEqual (bytes literal <> "\n") actual
    exists <- doesFileExist sentinel
    assertEqual False exists
    let global = directory </> "isolated-global-config"
    writeFile global "[user]\nname = Supplied Global Configuration\n"
    configured <-
        success
            (environment ++ [("GIT_CONFIG_GLOBAL", Just global)])
            directory
            ["config", "--get", "user.name"]
            BS.empty
    assertEqual "Supplied Global Configuration\n" configured

pipeTest :: [(String, Maybe String)] -> IO ()
pipeTest environment = withTempDirectory $ \directory -> do
    _ <- success environment directory ["init", "-q", "--initial-branch=main", "--object-format=sha1"] BS.empty
    let payload = BS.pack [0, 255, 10, 128] <> BS.replicate (256 * 1024) 120
    oidBytes <- success environment directory ["hash-object", "-w", "--stdin"] payload
    oid <- expectRight (parseObjectId Sha1 (stripLf oidBytes))
    actual <- success environment directory ["cat-file", "blob", Text.unpack (Encoding.decodeUtf8 (objectIdBytes oid))] BS.empty
    assertTrue "Binary stdin/stdout round-trip differs" (payload == actual)

failureTest :: [(String, Maybe String)] -> IO ()
failureTest environment = withTempDirectory $ \directory -> do
    result <- invoke environment directory ["this-is-not-a-git-command"] (BS.replicate (256 * 1024) 120)
    assertTrue "Git error status lost" (gitExitCode result /= ExitSuccess)
    assertTrue "Git stderr lost" (not (BS.null (gitStderr result)))

spawnTest :: IO ()
spawnTest = withTempDirectory $ \directory -> do
    result <-
        runGit (nativeGit (directory </> "nonexistent-executable")) $
            GitInvocation directory ["--version"] BS.empty []
    case result of
        Left (GitTransportError _) -> pure ()
        other -> ioError (userError ("Spawn error not classified: " ++ show other))

invalidInvocationTest :: IO ()
invalidInvocationTest = withTempDirectory $ \directory -> do
    let git = nativeGit (directory </> "nonexistent-executable")
    mapM_
        ( \invocation -> do
            result <- runGit git invocation
            case result of
                Left (InvalidGitInvocation _) -> pure ()
                other -> ioError (userError ("Invalid input was executed: " ++ show other))
        )
        [ GitInvocation directory ["bad\0argument"] BS.empty []
        , GitInvocation directory [] BS.empty [("bad=name", Just "value")]
        , GitInvocation directory [] BS.empty [("NAME", Just "bad\0value")]
        ]

nonRepositoryTest :: [(String, Maybe String)] -> IO ()
nonRepositoryTest environment = withTempDirectory $ \directory -> do
    result <- inspectRepository (nativeGit defaultGitExecutable) directory environment
    case result of
        Left (RepositoryGitError _ _) -> pure ()
        other -> ioError (userError ("Non-repository not diagnosed: " ++ show other))

repositoryTest :: [(String, Maybe String)] -> ObjectFormat -> IO ()
repositoryTest environment format = withTempDirectory $ \directory -> do
    let mainPath = directory </> "main space\nlambda-\955"
        barePath = directory </> "bare.git"
        linkedPath = directory </> "linked space"
        formatName = case format of Sha1 -> "sha1"; Sha256 -> "sha256"
        git = nativeGit defaultGitExecutable
    _ <-
        success
            environment
            directory
            ["init", "-q", "--initial-branch=main", "--object-format=" ++ formatName, mainPath]
            BS.empty
    initial <- expectRight =<< inspectRepository git mainPath environment
    assertEqual (Just (bytes mainPath)) (repositoryWorktree initial)
    assertEqual (bytes (mainPath </> ".git")) (repositoryGitDirectory initial)
    assertEqual (repositoryGitDirectory initial) (repositoryCommonDirectory initial)
    assertEqual False (repositoryIsBare initial)
    assertEqual format (repositoryObjectFormat initial)
    let nested = mainPath </> "nested"
    createDirectory nested
    fromNested <- expectRight =<< inspectRepository git nested environment
    assertEqual initial fromNested
    writeFile (mainPath </> "payload") "fixture\n"
    _ <- success environment mainPath ["add", "--", "payload"] BS.empty
    _ <- success environment mainPath ["commit", "-q", "-m", "fixture"] BS.empty
    _ <- success environment mainPath ["worktree", "add", "-q", "-b", "linked", linkedPath] BS.empty
    linked <- expectRight =<< inspectRepository git linkedPath environment
    assertEqual (Just (bytes linkedPath)) (repositoryWorktree linked)
    assertEqual (repositoryCommonDirectory initial) (repositoryCommonDirectory linked)
    assertTrue "Linked worktree private git directory lost" $
        repositoryGitDirectory linked /= repositoryCommonDirectory linked
    assertEqual format (repositoryObjectFormat linked)
    _ <-
        success
            environment
            directory
            ["init", "-q", "--bare", "--object-format=" ++ formatName, barePath]
            BS.empty
    bare <- expectRight =<< inspectRepository git barePath environment
    assertEqual Nothing (repositoryWorktree bare)
    assertEqual True (repositoryIsBare bare)
    assertEqual (bytes barePath) (repositoryCommonDirectory bare)
    assertEqual format (repositoryObjectFormat bare)
