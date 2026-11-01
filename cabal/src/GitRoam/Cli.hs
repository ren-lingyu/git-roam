{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Cli (
    Command (..),
    HelpTopic (..),
    CliResponse (..),
    parseCommand,
    runCli,
) where

import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Inspect
import GitRoam.BuildInfo (packageVersion)
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (ObjectProblem (..))
import GitRoam.Protocol.Repository
import System.Directory (getCurrentDirectory)
import System.Exit (ExitCode (..))

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp | CheckHelp | StatusHelp
    deriving (Eq, Show)

data Command = ShowHelp HelpTopic | ShowVersion | CheckNode (Maybe NodeId) | StatusNode (Maybe NodeId)
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
    ["help", "check"] -> help CheckHelp
    ["help", "status"] -> help StatusHelp
    ["check", "--help"] -> help CheckHelp
    ["check", "-h"] -> help CheckHelp
    ["status", "--help"] -> help StatusHelp
    ["status", "-h"] -> help StatusHelp
    ["check"] -> Right (CheckNode Nothing)
    ["status"] -> Right (StatusNode Nothing)
    ["check", "--node", node] -> CheckNode . Just <$> uuid node
    ["status", "--node", node] -> StatusNode . Just <$> uuid node
    "check" : _ -> Left "Usage: git roam check [--node <uuid>]"
    "status" : _ -> Left "Usage: git roam status [--node <uuid>]"
    ["help", topic] -> Left ("Unknown help topic: " <> quoted topic)
    "version" : _ -> Left "The version command takes no arguments."
    "help" : _ -> Left "Usage: git roam help [command]"
    option : _ | take 1 option == "-" -> Left ("Unknown option: " <> quoted option)
    command : _ -> Left ("Unknown command: " <> quoted command)
  where
    help = Right . ShowHelp
    quoted = Text.pack . show
    uuid node = either (const (Left ("Invalid Node UUID: " <> quoted node))) Right (parseNodeId (Encoding.encodeUtf8 (Text.pack node)))

renderHelp :: HelpTopic -> Text
renderHelp topic = case topic of
    GeneralHelp ->
        Text.unlines
            [ "usage: git roam <command> [options]"
            , ""
            , "Commands:"
            , "  help [command]  Show general or command-specific help"
            , "  version         Print the package version"
            , "  check           Validate Node history and managed dependencies"
            , "  status          Show Node history, dependencies and worktrees"
            , ""
            , "Options:"
            , "  -h, --help      Show general help"
            , "  --version       Print the package version"
            ]
    HelpHelp -> Text.unlines ["usage: git roam help [command]", "", "Show general help or help for an available command."]
    VersionHelp -> Text.unlines ["usage: git roam version", "       git roam --version", "", "Print the package version."]
    CheckHelp -> inspectionHelp "check" "Validate the complete protocol and managed dependency closure."
    StatusHelp -> inspectionHelp "status" "Show actual Node history, dependencies, worktrees and diagnostics."
  where
    inspectionHelp command description =
        Text.unlines
            [ "usage: git roam " <> command <> " [--node <uuid>]"
            , ""
            , description
            , "Select an explicit Node, infer the current Node worktree, or inspect the repository."
            , "Node scope includes the persistent branches needed by its retained history."
            , "Read-only; repository protection need not be enabled."
            ]

runCli :: [String] -> IO CliResponse
runCli arguments = case parseCommand arguments of
    Left message -> pure (failure 2 (message <> "\nTry 'git roam --help' for usage."))
    Right (ShowVersion) -> pure (success ("git-roam " <> Text.pack packageVersion <> "\n"))
    Right (ShowHelp topic) -> pure (success (renderHelp topic))
    Right (CheckNode node) -> inspect False node
    Right (StatusNode node) -> inspect True node
  where
    inspect status requested = do
        directory <- getCurrentDirectory
        let git = nativeGit defaultGitExecutable
        selected <- case requested of
            Just node -> pure (Right (Just node))
            Nothing -> inferNode git directory
        outcome <- case selected of
            Left problem -> pure (Left problem)
            Right node -> inspectState git directory [] node
        pure $ case outcome of
            Left problem -> failure (inspectionExit problem) (inspectionDiagnostic problem)
            Right report ->
                let issues = reportProblems report
                    output =
                        if status
                            then renderStatus report
                            else
                                if null issues
                                    then "OK: " <> decimal (length (reportNodes report)) <> " Nodes; history and managed dependencies are valid.\n"
                                    else ""
                    errors = Text.concat ["git-roam: " <> stateDiagnostic issue <> "\n" | issue <- issues]
                 in CliResponse (if null issues then ExitSuccess else ExitFailure 1) output errors
    success output = CliResponse ExitSuccess output ""
    failure code message = CliResponse (ExitFailure code) "" ("git-roam: " <> message <> "\n")

decimal :: Int -> Text
decimal = Text.pack . show

nodeText :: NodeId -> Text
nodeText = Text.pack . BSC.unpack . nodeIdBytes

oidText :: ObjectId -> Text
oidText = Text.pack . BSC.unpack . objectIdBytes

stateDiagnostic :: StateProblem -> Text
stateDiagnostic issue = case issue of
    UnknownNodeTip node tip -> "history-unavailable: " <> nodeText node <> " points to unknown " <> oidText tip
    RefIdentityMismatch node actual tip -> "identity-mismatch: branch " <> nodeText node <> " points to Node " <> nodeText actual <> " at " <> oidText tip
    MissingDependencyBranch from node oid -> "missing-node-branch: " <> oidText from <> " requires " <> nodeText node <> " at " <> oidText oid
    DependencyVersionNotRetained from node oid -> "version-not-retained: " <> oidText from <> " requires " <> nodeText node <> " at " <> oidText oid

inspectionExit :: InspectionError -> Int
inspectionExit problem = case problem of
    HistoryFailure (ObjectUnavailable _ (WrongObjectType _)) -> 1
    HistoryFailure (ObjectUnavailable _ _) -> 3
    HistoryFailure _ -> 1
    SymbolicNodeBranch _ _ -> 1
    NodeNotManaged _ -> 1
    _ -> 3

inspectionDiagnostic :: InspectionError -> Text
inspectionDiagnostic problem = case problem of
    HistoryFailure (ObjectUnavailable oid (WrongObjectType kind)) -> "object-type-mismatch: " <> oidText oid <> " has type " <> Text.pack (show kind)
    ReferencesChanged -> "observation-changed: Node refs changed during inspection; run the command again."
    ShallowRepository -> "history-incomplete: shallow repositories cannot establish complete Node history."
    MissingReachableObjects objects -> "objects-missing: " <> Text.intercalate ", " (map (Text.pack . BSC.unpack) objects)
    NodeNotManaged node -> "node-not-managed: no local branch for " <> nodeText node
    SymbolicNodeBranch node target -> "symbolic-node-branch: " <> nodeText node <> " points to " <> Text.pack (show target)
    HistoryFailure (ObjectUnavailable oid reason) -> "history-unavailable: " <> oidText oid <> " " <> Text.pack (show reason)
    HistoryFailure reason -> "history-invalid: " <> Text.pack (show reason)
    _ -> "git-read-failure: " <> Text.pack (show problem)

renderStatus :: InspectionReport -> Text
renderStatus report
    | null (reportNodes report) = "No managed Nodes.\n"
    | otherwise = Text.concat (map renderNode (reportNodes report))
  where
    renderNode node =
        Text.unlines $
            [ "node " <> nodeText (viewNode node)
            , "  tip " <> oidText (viewTip node) <> " (" <> kind (viewKind node) <> ")"
            , "  checkpoint " <> maybe "none" oidText (viewLatestCheckpoint node)
            , "  content-tail " <> (case viewKind node of Content _ _ -> "yes"; _ -> "no")
            , "  retained-checkpoints " <> decimal (viewFormalCount node)
            , "  dependencies " <> dependencyLabel node
            ]
                ++ ["    " <> nodeText dep <> " " <> oidText oid | (dep, oid) <- Map.toList (viewDependencies node)]
                ++ [ "  worktree " <> Text.pack (show (worktreePath worktree)) <> if worktreeIsMain worktree then " (main; not a removable deployment)" else " (linked)"
                   | worktree <- reportWorktrees report
                   , worktreeNode worktree == Just (viewNode node)
                   ]
    kind Root = "root"
    kind (Content _ _) = "content"
    kind (Checkpoint _) = "checkpoint"
    dependencyLabel node = case viewLatestCheckpoint node of
        Nothing -> "not declared (no Checkpoint)"
        Just _ ->
            (case viewKind node of Content _ _ -> "of latest Checkpoint"; _ -> "complete")
                <> if Map.null (viewDependencies node) then ": none" else ":"
