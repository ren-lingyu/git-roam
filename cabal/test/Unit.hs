{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.Text as Text
import GitRoam.Cli
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Repository
import System.Exit (ExitCode (..))
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
                (\args -> runCli args >>= assertEqual (CliResponse ExitSuccess "git-roam 0.1.0\n" ""))
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
                assertTrue "help missing" ("help [command]" `Text.isInfixOf` output)
                assertTrue "Node deletion missing" ("node delete" `Text.isInfixOf` output)
                assertTrue "unimplemented command advertised" $
                    not ("node adopt" `Text.isInfixOf` output)
            )
        ,
            ( "object formats"
            , do
                assertEqual (Right Sha1) (parseObjectFormat "sha1")
                assertEqual (Right Sha256) (parseObjectFormat "sha256")
                expectLeft (parseObjectFormat "unknown")
            )
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
