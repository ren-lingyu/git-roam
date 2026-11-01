{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Cli (
    Command (..),
    HelpTopic (..),
    CliResponse (..),
    CheckpointMessage (..),
    parseCommand,
    runCli,
) where

import Control.Exception (IOException, try)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Checkpoint as Checkpoints
import qualified GitRoam.Application.Create as Creation
import qualified GitRoam.Application.Deploy as Deployment
import GitRoam.Application.Inspect
import qualified GitRoam.Application.Protection as Protection
import qualified GitRoam.Application.Undeploy as Undeployment
import GitRoam.BuildInfo (packageVersion)
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (ObjectProblem (..))
import GitRoam.Protocol.Repository
import System.Directory (getCurrentDirectory)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp | CheckHelp | StatusHelp | EnableHelp | DisableHelp | DeployHelp | UndeployHelp | NodeHelp | NodeCreateHelp | CheckpointHelp
    deriving (Eq, Show)

data CheckpointMessage = InlineMessage String | FileMessage FilePath deriving (Eq, Show)

data Command = ShowHelp HelpTopic | ShowVersion | CheckNode (Maybe NodeId) | StatusNode (Maybe NodeId) | EnableProtection | DisableProtection | DeployNodes FilePath (Maybe String) | UndeployNodes | CreateNode FilePath | CreateCheckpoint (Maybe NodeId) CheckpointMessage Checkpoints.DependencyEdits
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
    ["help", "enable"] -> help EnableHelp
    ["help", "disable"] -> help DisableHelp
    ["help", "deploy"] -> help DeployHelp
    ["help", "undeploy"] -> help UndeployHelp
    ["help", "checkpoint"] -> help CheckpointHelp
    ["checkpoint", "--help"] -> help CheckpointHelp
    ["checkpoint", "-h"] -> help CheckpointHelp
    "checkpoint" : args -> checkpointArgs Nothing Nothing False [] [] args
    ["help", "node"] -> help NodeHelp
    ["help", "node", "create"] -> help NodeCreateHelp
    ["node"] -> help NodeHelp
    ["node", "--help"] -> help NodeHelp
    ["node", "-h"] -> help NodeHelp
    ["node", "create", "--help"] -> help NodeCreateHelp
    ["node", "create", "-h"] -> help NodeCreateHelp
    ["node", "create", "--path", path] | validValue path -> Right (CreateNode path)
    "node" : _ -> Left "Usage: git roam node create --path <path>"
    ["undeploy", "--help"] -> help UndeployHelp
    ["undeploy", "-h"] -> help UndeployHelp
    ["undeploy"] -> Right UndeployNodes
    "undeploy" : _ -> Left "Usage: git roam undeploy"
    ["deploy", "--help"] -> help DeployHelp
    ["deploy", "-h"] -> help DeployHelp
    ["deploy", "--path", path] | validValue path -> Right (DeployNodes path Nothing)
    ["deploy", "--path", path, "--remote", remote] | validValue path && validValue remote -> Right (DeployNodes path (Just remote))
    ["deploy", "--remote", remote, "--path", path] | validValue path && validValue remote -> Right (DeployNodes path (Just remote))
    "deploy" : _ -> Left "Usage: git roam deploy --path <path> [--remote <remote>]"
    ["enable", "--help"] -> help EnableHelp
    ["disable", "--help"] -> help DisableHelp
    ["enable", "-h"] -> help EnableHelp
    ["disable", "-h"] -> help DisableHelp
    ["enable"] -> Right EnableProtection
    ["disable"] -> Right DisableProtection
    "enable" : _ -> Left "Usage: git roam enable"
    "disable" : _ -> Left "Usage: git roam disable"
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
    validValue value = not (null value) && take 1 value /= "-" && '\0' `notElem` value
    quoted = Text.pack . show
    uuid node = either (const (Left ("Invalid Node UUID: " <> quoted node))) Right (parseNodeId (Encoding.encodeUtf8 (Text.pack node)))
    checkpointArgs node message clear drops adds args = case args of
        [] -> case message of
            Nothing -> Left "Checkpoint requires exactly one -m or -F message"
            Just text -> Right (CreateCheckpoint node text (Checkpoints.DependencyEdits clear (reverse drops) (reverse adds)))
        "--node" : value : rest | node == Nothing -> uuid value >>= \selected -> checkpointArgs (Just selected) message clear drops adds rest
        "-m" : value : rest | message == Nothing -> checkpointArgs node (Just (InlineMessage value)) clear drops adds rest
        "-F" : value : rest | message == Nothing && not (null value) && '\0' `notElem` value -> checkpointArgs node (Just (FileMessage value)) clear drops adds rest
        "--depend" : value : rest | not (null value) && '\0' `notElem` value -> checkpointArgs node message clear drops (value : adds) rest
        "--drop-dependency" : value : rest -> uuid value >>= \dep -> checkpointArgs node message clear (dep : drops) adds rest
        "--clear-dependencies" : rest | not clear -> checkpointArgs node message True drops adds rest
        _ -> Left "Usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>) [--depend <revision>] [--drop-dependency <uuid>] [--clear-dependencies]"

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
            , "  enable          Enable repository reference protection"
            , "  disable         Disable protection after full undeployment"
            , "  deploy          Deploy all local and fetched candidate Nodes"
            , "  undeploy        Safely remove all Node linked worktrees"
            , "  node create     Create a Node and editable linked worktree"
            , "  checkpoint      Confirm committed Content and complete dependencies"
            , ""
            , "Options:"
            , "  -h, --help      Show general help"
            , "  --version       Print the package version"
            ]
    HelpHelp -> Text.unlines ["usage: git roam help [command]", "", "Show general help or help for an available command."]
    VersionHelp -> Text.unlines ["usage: git roam version", "       git roam --version", "", "Print the package version."]
    CheckHelp -> inspectionHelp "check" "Validate the complete protocol and managed dependency closure."
    StatusHelp -> inspectionHelp "status" "Show actual Node history, dependencies, worktrees and diagnostics."
    EnableHelp -> Text.unlines ["usage: git roam enable", "", "Enable this executable's named repository Hook without changing knowledge history."]
    DisableHelp -> Text.unlines ["usage: git roam disable", "", "Remove Git-roam protection after all Node linked worktrees have been undeployed."]
    DeployHelp -> Text.unlines ["usage: git roam deploy --path <path> [--remote <remote>]", "", "Deploy all local Nodes and canonical fetched candidates under eight-character UUID directories.", "--remote limits discovery of missing Nodes to that remote; local branches are never advanced.", "Requires enabled protection. Does not fetch, merge or relocate existing worktrees.", "Failures report residual state after conservative compensation; no filesystem atomicity is promised."]
    UndeployHelp -> Text.unlines ["usage: git roam undeploy", "", "Remove all Node linked worktrees, including manually created or moved ones.", "Requires enabled protection and valid managed history. Every target is preflighted before removal.", "Retains branches, history, protection and main/detached/unmanaged worktrees.", "No subset, path, force or automatic rollback; partial failures report actual remaining state."]
    NodeHelp -> Text.unlines ["usage: git roam node <command>", "", "Commands:", "  create --path <path>  Create a UUIDv4 Node with an editable linked worktree"]
    NodeCreateHelp -> Text.unlines ["usage: git roam node create --path <path>", "", "Create a UUIDv4 identity, empty-marker Root, persistent local branch and linked worktree.", "Requires enabled matching protection and valid managed history. Uses native Git author/committer configuration.", "Reports UUID, Root OID and actual path; existing Nodes are not deployed or advanced.", "Failures compensate only proven new unchanged state; user changes and uncertain results are retained."]
    CheckpointHelp -> Text.unlines ["usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>)", "       [--depend <ref-or-oid>] [--drop-dependency <uuid>] [--clear-dependencies]", "", "Select an explicit Node or infer its worktree; Root requires committed Content first.", "Messages must be nonempty UTF-8 text without NUL. -F - reads stdin; no editor is started.", "Inherit the previous full dependency set; --depend adds/replaces one external Checkpoint per UUID.", "Dependencies accept Git refs and unambiguous commit OIDs, including abbreviations; no revision expressions.", "Repeat --depend/--drop-dependency for different Nodes. Clear may combine with additions, not removals.", "Conflicting edits, self dependencies and unretained/non-Checkpoint inputs are refused.", "Uses the committed tree, preserving all Content history and uncommitted index/worktree data."]
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
runCli ["--reference-transaction", phase] | phase `elem` ["preparing", "prepared", "committed", "aborted"] = do
    directory <- getCurrentDirectory
    input <- BSC.getContents
    result <- Protection.evaluateTransaction directory phase input
    pure $ case result of
        Right () -> CliResponse ExitSuccess "" ""
        Left problem -> CliResponse (ExitFailure 1) "" ("git-roam: reference update refused: " <> Text.pack problem <> "\n")
runCli arguments = case parseCommand arguments of
    Left message -> pure (failure 2 (message <> "\nTry 'git roam --help' for usage."))
    Right (ShowVersion) -> pure (success ("git-roam " <> Text.pack packageVersion <> "\n"))
    Right (ShowHelp topic) -> pure (success (renderHelp topic))
    Right (CheckNode node) -> inspect False node
    Right (StatusNode node) -> inspect True node
    Right EnableProtection -> lifecycle Protection.enableProtection "Repository protection enabled.\n"
    Right DisableProtection -> lifecycle Protection.disableProtection "Repository protection disabled.\n"
    Right (CreateCheckpoint node source edits) -> do
        loaded <-
            try
                ( case source of
                    InlineMessage text -> pure (Encoding.encodeUtf8 (Text.pack text))
                    FileMessage "-" -> BS.getContents
                    FileMessage path -> BS.readFile path
                )
        case loaded of
            Left problem -> pure (failure 1 ("Cannot read Checkpoint message: " <> Text.pack (show (problem :: IOException))))
            Right message -> do
                directory <- getCurrentDirectory
                executable <- getExecutablePath
                result <- Checkpoints.checkpoint executable (nativeGit defaultGitExecutable) directory node message edits
                pure $ case result of
                    Left (Checkpoints.CheckpointFailure reason details) -> failure 1 (Text.unlines (Text.pack reason : map Text.pack details))
                    Right value ->
                        success
                            ( Text.unlines
                                ( ["node " <> nodeText (Checkpoints.checkpointNode value), "checkpoint " <> oidText (Checkpoints.checkpointOid value), "content " <> oidText (Checkpoints.checkpointContent value)]
                                    ++ ["dependency " <> nodeText dep <> " " <> oidText oid | (dep, oid) <- Map.toList (Checkpoints.checkpointDependencies value)]
                                )
                            )
    Right (CreateNode path) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        result <- Creation.createNode executable (nativeGit defaultGitExecutable) directory path
        pure $ case result of
            Left (Creation.CreationFailure reason details) -> failure 1 (Text.unlines (Text.pack reason : map Text.pack details))
            Right report -> success (Text.unlines ["node " <> nodeText (Creation.createdNode report), "root " <> oidText (Creation.createdRoot report), "worktree " <> Text.pack (show (Creation.createdPath report))])
    Right UndeployNodes -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        result <- Undeployment.undeploy executable (nativeGit defaultGitExecutable) directory
        pure $ case result of
            Left (Undeployment.UndeploymentFailure reason details) -> failure 1 (Text.unlines (Text.pack reason : map Text.pack details))
            Right report ->
                success
                    ( Text.unlines
                        ( ["Undeployed " <> decimal (length (Undeployment.removedWorktrees report)) <> " Node linked worktrees."]
                            ++ ["removed " <> nodeText node <> " " <> Text.pack (show path) | (node, path) <- Undeployment.removedWorktrees report]
                            ++ ["retained main " <> nodeText node <> " " <> Text.pack (show path) | (node, path) <- Undeployment.retainedMainNodes report]
                        )
                    )
    Right (DeployNodes path remote) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        result <- Deployment.deploy executable (nativeGit defaultGitExecutable) directory path remote
        pure $ case result of
            Left (Deployment.DeploymentFailure reason details) -> failure 1 (Text.unlines (Text.pack reason : map Text.pack details))
            Right report ->
                success
                    ( Text.unlines
                        ( ["Deployed " <> decimal (length (Deployment.deployedWorktrees report)) <> " Nodes."]
                            ++ [nodeText node <> " " <> Text.pack (show target) | (node, target) <- Deployment.deployedWorktrees report]
                            ++ ["tracking " <> nodeText node <> " " <> Text.pack (show ref) | (node, ref) <- Deployment.trackingSources report]
                        )
                    )
  where
    lifecycle operation message = do
        directory <- getCurrentDirectory
        result <- operation directory
        pure $ either (failure 1 . Text.pack) (const (success message)) result
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
