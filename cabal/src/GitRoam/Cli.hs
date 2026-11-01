{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Cli (
    Command (..),
    HelpTopic (..),
    CliResponse (..),
    parseCommand,
    renderCommand,
    runCli,
) where

import Data.Text (Text)
import qualified Data.Text as Text
import GitRoam.BuildInfo (packageVersion)
import System.Exit (ExitCode (..))

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp
    deriving (Eq, Show)

data Command = ShowHelp HelpTopic | ShowVersion
    deriving (Eq, Show)

data CliResponse = CliResponse
    { responseExitCode :: ExitCode
    , responseStdout :: Text
    , responseStderr :: Text
    }
    deriving (Eq, Show)

parseCommand :: [String] -> Either Text Command
parseCommand arguments = case arguments of
    [] -> help GeneralHelp
    ["-h"] -> help GeneralHelp
    ["--help"] -> help GeneralHelp
    ["--version"] -> Right ShowVersion
    ["version"] -> Right ShowVersion
    ["version", "-h"] -> help VersionHelp
    ["version", "--help"] -> help VersionHelp
    ["help"] -> help GeneralHelp
    ["help", "help"] -> help HelpHelp
    ["help", "-h"] -> help HelpHelp
    ["help", "--help"] -> help HelpHelp
    ["help", "version"] -> help VersionHelp
    ["help", topic] -> Left ("Unknown help topic: " <> quoted topic)
    "version" : _ -> Left "The version command takes no arguments."
    "help" : _ -> Left "Usage: git roam help [command]"
    option : _ | take 1 option == "-" -> Left ("Unknown option: " <> quoted option)
    command : _ -> Left ("Unknown command: " <> quoted command)
  where
    help = Right . ShowHelp
    quoted = Text.pack . show

renderCommand :: Command -> Text
renderCommand command = case command of
    ShowVersion -> "git-roam " <> Text.pack packageVersion <> "\n"
    ShowHelp GeneralHelp ->
        Text.unlines
            [ "usage: git roam <command> [options]"
            , ""
            , "Commands:"
            , "  help [command]  Show general or command-specific help"
            , "  version         Print the package version"
            , ""
            , "Options:"
            , "  -h, --help      Show general help"
            , "  --version       Print the package version"
            ]
    ShowHelp HelpHelp ->
        Text.unlines
            [ "usage: git roam help [command]"
            , ""
            , "Show general help or help for an available command."
            ]
    ShowHelp VersionHelp ->
        Text.unlines
            [ "usage: git roam version"
            , "       git roam --version"
            , ""
            , "Print the package version."
            ]

runCli :: [String] -> CliResponse
runCli arguments = case parseCommand arguments of
    Right command -> CliResponse ExitSuccess (renderCommand command) ""
    Left message ->
        CliResponse
            (ExitFailure 2)
            ""
            ("git-roam: " <> message <> "\nTry 'git roam --help' for usage.\n")
