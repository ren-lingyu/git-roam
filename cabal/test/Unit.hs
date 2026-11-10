{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.Text as Text
import GitRoam.Cli
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Repository
import System.Directory (doesPathExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport

main :: IO ()
main =
    runTests
        [
            ( "help entry points work without a repository"
            , mapM_
                (\args -> assertEqual (Right (ShowHelp GeneralHelp)) (parseCommand args))
                [[], ["help"], ["-h"], ["--help"]]
            )
        ,
            ( "command-specific help"
            , mapM_
                (\args -> assertEqual (Right (ShowHelp VersionHelp)) (parseCommand args))
                [["help", "version"], ["version", "--help"], ["version", "-h"]]
            )
        ,
            ( "version entry points agree"
            , mapM_
                (\args -> runCli args >>= assertEqual (CliResponse ExitSuccess "git-roam 0.2.0\n" ""))
                [["version"], ["--version"]]
            )
        ,
            ( "invalid arguments return usage failure on stderr"
            , mapM_
                checkInvalid
                [ ["unknown"]
                , ["node", "unknown"]
                , ["--unknown"]
                , ["--version", "extra"]
                , ["version", "extra"]
                , ["help", "unknown"]
                , ["discard"]
                , ["help", "discard"]
                , ["help", "version", "extra"]
                ]
            )
        ,
            ( "argument diagnostics escape newlines"
            , do
                response <- runCli ["bad\ncommand"]
                assertTrue "A raw newline leaked into the command name diagnostic" $
                    "bad\\ncommand" `Text.isInfixOf` responseStderr response
            )
        ,
            ( "help advertises only available commands"
            , do
                output <- responseStdout <$> runCli []
                assertTrue "help missing" ("help [command]" `BS.isInfixOf` output)
                assertTrue "Node deletion missing" ("node delete" `BS.isInfixOf` output)
                assertTrue "retired discard command advertised" $
                    not ("  discard " `BS.isInfixOf` output)
                assertTrue "unimplemented command advertised" $
                    not ("node adopt" `BS.isInfixOf` output)
            )
        ,
            ( "enable help documents PATH-resolved Hook"
            , do
                output <- responseStdout <$> runCli ["help", "enable"]
                assertTrue "Hook resolution is not documented" ("git-roam --reference-transaction" `BS.isInfixOf` output)
            )
        ,
            ( "object formats"
            , do
                assertEqual (Right Sha1) (parseObjectFormat "sha1")
                assertEqual (Right Sha256) (parseObjectFormat "sha256")
                expectLeft (parseObjectFormat "unknown")
            )
        , ("top-level deployment path supplies create/deploy", globalPathTest)
        , ("top-level deployment path rejects invalid prefixes", globalInvalidTest)
        , ("top-level and subcommand paths are mutually exclusive", globalConflictTest)
        , ("unused global paths preserve public command parsing", globalUnusedTest)
        , ("global parsing preserves option-like command values", globalValuesTest)
        , ("help and version never create the global deployment directory", globalHelpTest)
        , ("both OID lengths are supported", mapM_ checkOid [Sha1, Sha256])
        , ("OID format mismatch rejects", expectLeft (parseObjectId Sha1 (BS.replicate 64 97)))
        ,
            ( "invalid OIDs reject"
            , mapM_
                (expectLeft . parseObjectId Sha1)
                [BS.empty, BS.replicate 40 48, BS.replicate 40 65, BS.replicate 40 255]
            )
        ,
            ( "repository read failure is not absence"
            , do
                let failure = GitResult (ExitFailure 128) "" "fatal: fixture read failure\n"
                    git = Git (const (pure (Right failure)))
                result <- inspectRepository git "." []
                case result of
                    Left (RepositoryGitError _ actual) -> assertEqual failure actual
                    other -> ioError (userError ("Lost Git failure: " ++ show other))
            )
        ,
            ( "malformed Git output is indeterminate"
            , do
                let git = Git (const (pure (Right (GitResult ExitSuccess "maybe\n" ""))))
                result <- inspectRepository git "." []
                case result of
                    Left (RepositoryMalformedOutput _ "maybe") -> pure ()
                    other -> ioError (userError ("Accepted malformed output: " ++ show other))
            )
        ]
  where
    checkInvalid args = do
        response <- runCli args
        assertEqual (ExitFailure 2) (responseExitCode response)
        assertEqual "" (responseStdout response)
        assertTrue "Missing diagnostic prefix" ("git-roam: " `Text.isPrefixOf` responseStderr response)
    checkOid format = do
        let bytes = BS.replicate (objectIdLength format) 97
        oid <- expectRight (parseObjectId format bytes)
        assertEqual bytes (objectIdBytes oid)

globalPathTest :: IO ()
globalPathTest =
    mapM_
        equivalent
        [ ["node", "create"]
        , ["node", "create", "--id", "11111111-1111-4111-8111-111111111111", "--format", "json"]
        , ["node", "create", "--format", "cbor"]
        , ["deploy"]
        , ["deploy", "--remote", "origin"]
        ]
  where
    equivalent args = do
        let path = "/nodes with spaces"
        expected <- expectRight (parseCommand (args ++ ["--path", path]))
        actual <- expectRight (parseCommand (["--deploy-path", path] ++ args))
        assertEqual expected actual

globalInvalidTest :: IO ()
globalInvalidTest =
    mapM_
        invalid
        [ ["--deploy-path"]
        , ["--deploy-path", ""]
        , ["--deploy-path", "relative", "deploy"]
        , ["--deploy-path", ".", "node", "create"]
        , ["--deploy-path", "~/nodes", "--help"]
        , ["--deploy-path", "/bad\0path", "--version"]
        , ["--deploy-path", "/one", "--deploy-path", "/one", "deploy"]
        , ["--deploy-path", "/one", "--deploy-path", "/two", "node", "create"]
        , ["deploy", "--deploy-path", "/nodes"]
        , ["node", "create", "--deploy-path", "/nodes"]
        , ["--help", "--deploy-path", "/nodes"]
        ]
  where
    invalid args = do
        expectLeft (parseCommand args)
        response <- runCli args
        assertEqual (ExitFailure 2) (responseExitCode response)
        assertEqual BS.empty (responseStdout response)

globalConflictTest :: IO ()
globalConflictTest =
    mapM_
        rejected
        [ ["node", "create", "--path", "/nodes"]
        , ["node", "create", "--format", "json", "--path", "relative"]
        , ["deploy", "--path", "/nodes"]
        , ["deploy", "--remote", "origin", "--path", "/elsewhere"]
        ]
  where
    rejected args = do
        response <- runCli (["--deploy-path", "/nodes"] ++ args)
        assertEqual (ExitFailure 2) (responseExitCode response)
        assertTrue "Missing path-conflict diagnostic" ("mutually exclusive" `Text.isInfixOf` responseStderr response)

globalUnusedTest :: IO ()
globalUnusedTest =
    mapM_
        unchanged
        [ []
        , ["--help"]
        , ["--version"]
        , ["version"]
        , ["enable"]
        , ["disable"]
        , ["check"]
        , ["status"]
        , ["undeploy"]
        , ["help", "node", "create"]
        , ["node", "create", "--help"]
        , ["deploy", "--help"]
        , ["node", "delete", "--node", "11111111-1111-4111-8111-111111111111", "--dry-run"]
        ]
  where
    unchanged args = do
        expected <- expectRight (parseCommand args)
        actual <- expectRight (parseCommand (["--deploy-path", "/unused"] ++ args))
        assertEqual expected actual

globalValuesTest :: IO ()
globalValuesTest =
    mapM_
        unchanged
        [ ["checkpoint", "-m", "--path", "--context", "external"]
        , ["checkpoint", "-m", "--deploy-path", "--context", "external"]
        , ["checkpoint", "-F", "--deploy-path", "--context", "external"]
        ]
  where
    unchanged args = do
        expected <- expectRight (parseCommand args)
        actual <- expectRight (parseCommand (["--deploy-path", "/unused"] ++ args))
        assertEqual expected actual

globalHelpTest :: IO ()
globalHelpTest = withTempDirectory $ \parent -> do
    let path = parent </> "never-created"
    mapM_ (same path) [["--help"], ["help", "deploy"], ["help", "node", "create"], ["version"], ["--version"]]
    doesPathExist path >>= assertEqual False
  where
    same path args = do
        ordinary <- runCli args
        supplied <- runCli (["--deploy-path", path] ++ args)
        assertEqual ExitSuccess (responseExitCode supplied)
        assertEqual ordinary supplied
