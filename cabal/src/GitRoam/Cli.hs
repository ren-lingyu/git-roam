{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Cli (
    Command (..),
    HelpTopic (..),
    CliResponse (..),
    CheckpointMessage (..),
    parseCommand,
    runCli,
    statusResponse,
    checkResponse,
) where

import Control.Exception (IOException, try)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Check as Check
import qualified GitRoam.Application.Checkpoint as Checkpoints
import qualified GitRoam.Application.Create as Creation
import qualified GitRoam.Application.Delete as Deletion
import qualified GitRoam.Application.Deploy as Deployment
import qualified GitRoam.Application.Protection as Protection
import qualified GitRoam.Application.Status as Status
import qualified GitRoam.Application.Undeploy as Undeployment
import GitRoam.BuildInfo (packageVersion)
import qualified GitRoam.Diagnostic as Diagnostic
import GitRoam.Git
import GitRoam.Output (decimal, deleteFields, deleteValue, nodeText, nodeValue, oidText, oidValue, renderDelete, renderStatus, worktreePairs)
import qualified GitRoam.Output as Output
import GitRoam.Protocol.Identity
import GitRoam.Worktree.Paths (encodePath)
import System.Directory (getCurrentDirectory)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute)
import System.IO (hFlush, hIsTerminalDevice, stderr, stdin)

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp | CheckHelp | StatusHelp | EnableHelp | DisableHelp | DeployHelp | UndeployHelp | NodeHelp | NodeCreateHelp | NodeDeleteHelp | CheckpointHelp
    deriving (Eq, Show)

data CheckpointMessage = InlineMessage String | FileMessage FilePath deriving (Eq, Show)

data Command = Formatted Output.OutputFormat Command | ShowHelp HelpTopic | ShowVersion | CheckManagedState Bool | QueryStatus Status.StatusQuery | EnableProtection | DisableProtection | DeployNodes FilePath (Maybe String) | UndeployNodes | CreateNode FilePath (Maybe NodeId) | CreateCheckpoint (Maybe NodeId) CheckpointMessage [String] | PreviewDelete NodeId | ExecuteDelete NodeId (Maybe String)
    deriving (Eq, Show)

data CliResponse = CliResponse
    { responseExitCode :: ExitCode
    , responseStdout :: BS.ByteString
    , responseStderr :: Text
    }
    deriving (Eq, Show)

parseCommand :: [String] -> Either Text Command
parseCommand arguments = do
    (format, rest) <- parseFormat arguments
    (deployment, remaining) <- parseTopLevel rest
    command <- parseSubcommand deployment remaining
    pure (maybe command (`Formatted` command) format)

-- Only consume global prefix pairs; command arguments are opaque here.
parseFormat :: [String] -> Either Text (Maybe Output.OutputFormat, [String])
parseFormat = go Nothing []
  where
    go selected prefix ("--format" : value : rest)
        | Just _ <- selected = Left "Top-level --format cannot be repeated"
        | otherwise = do
            format <- case value of
                "text" -> Right Output.TextFormat
                "json" -> Right Output.JsonFormat
                "cbor" -> Right Output.CborFormat
                _ -> Left "Unknown output format (expected text, json, or cbor)"
            go (Just format) prefix rest
    go _ _ ["--format"] = Left "Top-level --format requires a value"
    go selected prefix ("--deploy-path" : value : rest) = go selected (prefix ++ ["--deploy-path", value]) rest
    go selected prefix rest = Right (selected, prefix ++ rest)

-- Only the prefix before the command contains global options. Values belonging
-- to subcommands (including messages named like options) are not scanned here.
parseTopLevel :: [String] -> Either Text (Maybe FilePath, [String])
parseTopLevel = go Nothing
  where
    go selected ("--deploy-path" : value : rest)
        | Just _ <- selected = Left "Top-level --deploy-path cannot be repeated"
        | isAbsolute value && '\0' `notElem` value = go (Just value) rest
        | otherwise = Left "Top-level --deploy-path requires an absolute path"
    go _ ["--deploy-path"] = Left "Top-level --deploy-path requires an absolute path"
    go selected remaining = Right (selected, remaining)

parseSubcommand :: Maybe FilePath -> [String] -> Either Text Command
parseSubcommand deployment arguments = case arguments of
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
    "checkpoint" : args -> checkpointArgs Nothing Nothing [] args
    ["help", "node"] -> help NodeHelp
    ["help", "node", "create"] -> help NodeCreateHelp
    ["help", "node", "delete"] -> help NodeDeleteHelp
    ["node", "delete", "--help"] -> help NodeDeleteHelp
    ["node", "delete", "-h"] -> help NodeDeleteHelp
    "node" : "delete" : args -> deleteArgs Nothing False Nothing args
    ["node"] -> help NodeHelp
    ["node", "--help"] -> help NodeHelp
    ["node", "-h"] -> help NodeHelp
    ["node", "create", "--help"] -> help NodeCreateHelp
    ["node", "create", "-h"] -> help NodeCreateHelp
    "node" : "create" : args -> createArgs Nothing Nothing args
    "node" : _ -> Left "Usage: git roam node create --path <path> [--id <uuid>]"
    ["undeploy", "--help"] -> help UndeployHelp
    ["undeploy", "-h"] -> help UndeployHelp
    ["undeploy"] -> Right UndeployNodes
    "undeploy" : _ -> Left "Usage: git roam undeploy"
    ["deploy", "--help"] -> help DeployHelp
    ["deploy", "-h"] -> help DeployHelp
    "deploy" : args -> deployArgs Nothing Nothing args
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
    ["check"] -> Right (CheckManagedState False)
    ["check", "--show-refs"] -> Right (CheckManagedState True)
    "check" : _ -> Left "Usage: git roam check [--show-refs]"
    "status" : args -> statusArgs Nothing [] [] args
    ["help", topic] -> Left ("Unknown help topic: " <> quoted topic)
    "version" : _ -> Left "The version command takes no arguments."
    "help" : _ -> Left "Usage: git roam help [command]"
    option : _ | take 1 option == "-" -> Left ("Unknown option: " <> quoted option)
    command : _ -> Left ("Unknown command: " <> quoted command)
  where
    statusArgs selected nodes properties args = case args of
        option : value : rest | option `elem` ["-t", "--type"], selected == Nothing, value `elem` ["repo", "node"] -> statusArgs (Just value) nodes properties rest
        option : value : rest | option `elem` ["-n", "--node"] -> uuid value >>= \node -> statusArgs selected (node : nodes) properties rest
        option : value : rest | option `elem` ["-p", "--property"] -> do
            property <- case value of
                "tip" -> Right Status.TipProperty
                "commit" -> Right Status.CommitProperty
                "worktrees" -> Right Status.WorktreesProperty
                "status" -> Right Status.StatusProperty
                "remote" -> Right Status.RemoteProperty
                _ -> Left "Unknown or unavailable Status property (expected tip, commit, worktrees, status, remote)"
            statusArgs selected nodes (property : properties) rest
        [] | selected == Just "repo", null nodes, null properties -> Right (QueryStatus Status.RepositoryStatus)
        [] | selected == Just "node" -> Right (QueryStatus (Status.NodeStatusQuery (if null nodes then Status.AllNodes else Status.SelectedNodes (Set.fromList nodes)) (if null properties then Status.DefaultProperties else Status.SelectedProperties (Set.fromList properties))))
        _ -> Left "Usage: git roam status -t repo | -t node [-n <uuid>]... [-p tip|commit|worktrees|status|remote]..."
    createArgs path node args = case args of
        [] -> CreateNode <$> deploymentPath path <*> pure node
        "--path" : value : rest | path == Nothing && validValue value -> createArgs (Just value) node rest
        "--id" : value : rest | node == Nothing -> uuid value >>= \selected -> createArgs path (Just selected) rest
        _ -> Left "Usage: git roam node create --path <path> [--id <uuid>]"
    deployArgs path remote args = case args of
        [] -> DeployNodes <$> deploymentPath path <*> pure remote
        "--path" : value : rest | path == Nothing && validValue value -> deployArgs (Just value) remote rest
        "--remote" : value : rest | remote == Nothing && validValue value -> deployArgs path (Just value) rest
        _ -> Left "Usage: git roam [--deploy-path <absolute-path>] deploy [--path <path>] [--remote <remote>]"
    deploymentPath path = case (deployment, path) of
        (Just _, Just _) -> Left "Top-level --deploy-path and subcommand --path are mutually exclusive"
        (Just target, Nothing) -> Right target
        (Nothing, Just target) -> Right target
        (Nothing, Nothing) -> Left "Provide a subcommand --path or top-level --deploy-path"
    deleteArgs node dry confirmation args = case args of
        "--node" : value : rest | node == Nothing -> case uuid value of
            Right parsed -> deleteArgs (Just parsed) dry confirmation rest
            Left _ -> Left "Node deletion requires a canonical UUID"
        "--dry-run" : rest | not dry && confirmation == Nothing -> deleteArgs node True confirmation rest
        "--confirm" : value : rest | not dry && confirmation == Nothing && length value == 64 && all (`elem` ("0123456789abcdef" :: String)) value -> deleteArgs node False (Just value) rest
        [] | Just selected <- node -> Right (if dry then PreviewDelete selected else ExecuteDelete selected confirmation)
        _ -> Left "Usage: git roam node delete --node <uuid> [--dry-run | --confirm <plan-id>]"
    help = Right . ShowHelp
    validValue value = not (null value) && take 1 value /= "-" && '\0' `notElem` value
    quoted = Text.pack . show
    uuid node = either (const (Left ("Invalid Node UUID: " <> quoted node))) Right (parseNodeId (Encoding.encodeUtf8 (Text.pack node)))
    checkpointArgs node message contexts args = case args of
        [] -> case (message, reverse contexts) of
            (Nothing, _) -> Left "Checkpoint requires exactly one -m or -F message"
            (Just _, []) -> Left "Checkpoint requires at least one --context revision"
            (Just text, selected) -> Right (CreateCheckpoint node text selected)
        "--node" : value : rest | node == Nothing -> uuid value >>= \selected -> checkpointArgs (Just selected) message contexts rest
        "-m" : value : rest | message == Nothing -> checkpointArgs node (Just (InlineMessage value)) contexts rest
        "-F" : value : rest | message == Nothing && not (null value) && '\0' `notElem` value -> checkpointArgs node (Just (FileMessage value)) contexts rest
        "--context" : value : rest | not (null value) && '\0' `notElem` value && take 1 value /= "-" -> checkpointArgs node message (value : contexts) rest
        _ -> Left "Usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>) --context <revision> [--context <revision> ...]"

renderHelp :: HelpTopic -> Text
renderHelp topic = case topic of
    GeneralHelp ->
        Text.unlines
            [ "usage: git roam [--format text|json|cbor] [--deploy-path <absolute-path>] <command> [options]"
            , ""
            , "Commands:"
            , "  help [command]  Show general or command-specific help"
            , "  version         Print the package version"
            , "  check           Validate Node history and recorded contexts"
            , "  status          Observe repository protection or selected Node properties"
            , "  enable          Install or verify repository reference protection"
            , "  disable         Disable protection after full undeployment"
            , "  deploy          Deploy all local and fetched candidate Nodes"
            , "  undeploy        Safely remove all Node linked worktrees"
            , "  node create     Create a Node and editable linked worktree"
            , "  node delete     Delete an unchecked-out local Node without cascading"
            , "  checkpoint      Record a Checkpoint with explicit context parents"
            , ""
            , "Options:"
            , "  -h, --help      Show general help"
            , "  --version       Print the package version"
            , "  --format text|json|cbor"
            , "                  Result encoding; place before the command (default: text)"
            , "  --deploy-path <absolute-path>"
            , "                  Deployment root for node create/deploy; mutually exclusive with --path"
            , "                  Place before the command; other commands do not use the directory"
            ]
    HelpHelp -> Text.unlines ["usage: git roam help [command]", "", "Show general help or help for an available command."]
    VersionHelp -> Text.unlines ["usage: git roam version", "       git roam --version", "", "Print the package version."]
    CheckHelp -> Text.unlines ["usage: git roam check [--show-refs]", "", "Validate the complete local managed state exposed by native Git ref enumeration.", "Always checks all enumerated local Node branches and reachable stored history/objects.", "--show-refs adds the initial full refname/OID map without changing validation.", "valid exits 0, invalid exits 1, inconclusive exits 3; argument errors exit 2.", "No worktree, protection configuration or transition checks. Read-only, no network.", "Native enumeration can silently omit dangling symbolic refs; this is a known detection limit."]
    StatusHelp -> Text.unlines ["usage: git roam status -t repo", "       git roam status -t node [-n <uuid>]... [-p tip|commit|worktrees|status|remote]...", "", "--type/-t is required exactly once. Repo rejects --node/-n and --property/-p.", "Node queries default to all canonical local Node branches and tip, worktrees, remote.", "Repeat --node/-n or --property/-p for set selection; properties are exact, not additive.", "Global --format belongs before status. No history validation or network query. Only -p status scans worktree files.", "Remote observations use local refs and upstream configuration. Partial reads have diagnostics and nonzero exit.", "Commit metadata reads only selected tips as raw bytes, without mailmap or encoding conversion. Status verifies worktree identity and reports clean, dirty or unavailable per path. Clean does not establish removal safety."]
    EnableHelp -> Text.unlines ["usage: git roam enable", "", "Install or validate the repository-local reference-transaction Hook.", "The Hook runs git-roam --reference-transaction from Git's PATH, not a pinned executable path.", "An existing canonical Hook is unchanged; recognized old absolute-path Git-roam Hooks are migrated.", "Incomplete, inherited or divergent configuration is refused; Node history is not changed."]
    DisableHelp -> Text.unlines ["usage: git roam disable", "", "Remove Git-roam protection after all Node linked worktrees have been undeployed."]
    DeployHelp -> Text.unlines ["usage: git roam deploy --path <path> [--remote <remote>]", "       git roam --deploy-path <absolute-path> deploy [--remote <remote>]", "", "Provide exactly one path source; top-level --deploy-path and subcommand --path are mutually exclusive.", "Deploy all local Nodes and canonical fetched candidates under eight-character UUID directories.", "--remote limits discovery of missing Nodes to that remote; local branches are never advanced.", "Requires enabled protection. Does not fetch, merge or relocate existing worktrees.", "Failures report residual state after conservative compensation; no filesystem atomicity is promised."]
    UndeployHelp -> Text.unlines ["usage: git roam undeploy", "", "Remove all Node linked worktrees, including manually created or moved ones.", "Requires enabled protection and valid managed history. Every target is preflighted before removal.", "Retains branches, history, protection and main/detached/unmanaged worktrees.", "No subset, path, force or automatic rollback; partial failures report actual remaining state."]
    NodeHelp -> Text.unlines ["usage: git roam node <command>", "", "Commands:", "  create [--path <path>] [--id <uuid>]  Create a Node with an editable linked worktree", "    Requires subcommand --path or top-level --deploy-path, not both.", "  delete --node <uuid>  Preview or confirm non-cascading Node deletion"]
    NodeDeleteHelp -> Text.unlines ["usage: git roam node delete --node <uuid> [--dry-run | --confirm <plan-id>]", "", "Preview removal of the explicit local UUID branch and its reviewed local branch configuration.", "Deletion does not cascade into other Nodes whose history records contexts from this Node.", "The preview lists commits that become unreachable from the remaining managed refs; Git objects are not erased.", "Any main or linked worktree checking out this branch blocks deletion; no implicit undeploy.", "--dry-run is read-only. Execution requires enabled protection and the complete plan ID.", "Without --confirm, terminal input/stderr are required to review and type the plan ID.", "No cascade, force, object erasure or recovery guarantee; remote refs and other Nodes are retained.", "A later deploy may recreate the Node from fetched remote candidates."]
    NodeCreateHelp -> Text.unlines ["usage: git roam node create --path <path> [--id <uuid>]", "       git roam --deploy-path <absolute-path> node create [--id <uuid>]", "", "Provide exactly one path source; top-level --deploy-path and subcommand --path are mutually exclusive.", "Create an identity, empty-marker Root, persistent local branch and linked worktree.", "--id accepts UUIDv4, Nil UUID or Max UUID; without it, a fresh UUIDv4 is generated.", "Top-level --format text (default) preserves the existing output; json and cbor provide structured machine output.", "JSON paths contain UTF-8 text when valid plus a lossless Base64 byte representation; CBOR paths are byte strings.", "Requires enabled matching protection and valid managed history. Uses native Git author/committer configuration.", "Reports UUID, Root OID, actual worktree path and UUID bundle path; existing Nodes are not deployed or advanced.", "Failures compensate only proven new unchanged state; user changes and uncertain results are retained."]
    CheckpointHelp -> Text.unlines ["usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>)", "       --context <revision> [--context <revision> ...]", "", "Select an explicit Node or infer it from the current Node worktree. A Checkpoint may directly follow Root.", "Messages must be nonempty UTF-8 text without NUL. -F - reads stdin; no editor is started.", "Each --context selects one external commit parent; argument order determines parent order.", "Contexts accept Git refs and unambiguous commit OIDs, including abbreviations; no revision expressions.", "A context may be a Root, Content or Checkpoint and need not be retained by its Node's current branch.", "Duplicate context OIDs and contexts belonging to the target Node are refused.", "Multiple distinct contexts from one external Node are accepted with a compatibility warning.", "Uses the current committed tree, preserving uncommitted index/worktree data."]

interactiveDelete :: FilePath -> NodeId -> IO (Either String BS.ByteString)
interactiveDelete directory node = do
    result <- try $ do
        inputTerminal <- hIsTerminalDevice stdin
        outputTerminal <- hIsTerminalDevice stderr
        if not (inputTerminal && outputTerminal)
            then pure (Left "Noninteractive Node deletion requires --dry-run review followed by --confirm <plan-id>")
            else do
                outcome <- Deletion.previewDelete (nativeGit defaultGitExecutable) directory node
                case outcome of
                    Left problem -> pure (Left problem)
                    Right report -> do
                        BS.hPut stderr (Encoding.encodeUtf8 (renderDelete report))
                        case Deletion.deletePlanId report of
                            Nothing -> pure (Left "Node deletion preview is blocked")
                            Just identifier -> do
                                BSC.hPutStr stderr "Type this plan ID to delete the Node: "
                                hFlush stderr
                                answer <- BSC.hGetLine stdin
                                pure (if answer == identifier then Right identifier else Left "Node deletion declined; no changes were made")
    pure $ either (Left . show) id (result :: Either IOException (Either String BS.ByteString))

-- Internal Hook dispatch is independent of public top-level option validation.
-- Ignore complete --format and --deploy-path pairs prepended by PATH wrappers;
-- the Hook never reads their values.
referenceTransactionPhase :: [String] -> Maybe String
referenceTransactionPhase ["--reference-transaction", phase]
    | phase `elem` ["preparing", "prepared", "committed", "aborted"] = Just phase
referenceTransactionPhase ("--format" : _ : remaining) = referenceTransactionPhase remaining
referenceTransactionPhase ("--deploy-path" : _ : remaining) = referenceTransactionPhase remaining
referenceTransactionPhase _ = Nothing

runCli :: [String] -> IO CliResponse
runCli arguments = case referenceTransactionPhase arguments of
    Just phase -> do
        directory <- getCurrentDirectory
        input <- BSC.getContents
        result <- Protection.evaluateTransaction (nativeGit defaultGitExecutable) directory phase input
        pure $ case result of
            Right () -> CliResponse ExitSuccess "" ""
            Left problem -> CliResponse (ExitFailure 1) "" ("git-roam: reference update refused: " <> Text.pack problem <> "\n")
    Nothing -> case parseCommand arguments of
        Left message -> runFormatted (diagnosticFormat arguments) (Left message)
        parsed -> runParsedCommand parsed

-- Retain the first valid format for diagnostics if later argument parsing fails.
diagnosticFormat :: [String] -> Output.OutputFormat
diagnosticFormat ("--format" : "json" : _) = Output.JsonFormat
diagnosticFormat ("--format" : "cbor" : _) = Output.CborFormat
diagnosticFormat ("--deploy-path" : _ : rest) = diagnosticFormat rest
diagnosticFormat _ = Output.TextFormat

runParsedCommand :: Either Text Command -> IO CliResponse
runParsedCommand = runFormatted Output.TextFormat

runFormatted :: Output.OutputFormat -> Either Text Command -> IO CliResponse
runFormatted format parsed = case parsed of
    Right (Formatted selected command) -> runFormatted selected (Right command)
    Left message -> pure (failure 2 (message <> "\nTry 'git roam --help' for usage."))
    Right (ShowVersion) -> pure (resultResponse [("version", Output.String (Text.pack packageVersion))] ("git-roam " <> Text.pack packageVersion <> "\n"))
    Right (ShowHelp topic) -> pure (success (renderHelp topic))
    Right (CheckManagedState showRefs) -> do
        directory <- getCurrentDirectory
        outcome <- Check.checkManagedState (nativeGit defaultGitExecutable) directory
        pure $ case outcome of
            Left problem -> diagnosticFailure 3 "repository_discovery_failed" (Text.pack (show problem))
            Right report -> checkResponse format showRefs report
    Right (QueryStatus request) -> do
        directory <- getCurrentDirectory
        outcome <- Status.queryStatus (nativeGit defaultGitExecutable) directory request
        pure $ case outcome of
            Left problem -> if format == Output.TextFormat then failure 3 (Text.pack (show problem)) else diagnosticFailure 3 "repository_discovery_failed" (Text.pack (show problem))
            Right report -> statusResponse format report
    Right EnableProtection -> lifecycle Protection.enableProtection "Repository protection enabled.\n"
    Right DisableProtection -> lifecycle Protection.disableProtection "Repository protection disabled.\n"
    Right (PreviewDelete node) -> do
        directory <- getCurrentDirectory
        result <- Deletion.previewDelete (nativeGit defaultGitExecutable) directory node
        pure $ case result of
            Left problem -> failure 1 (Text.pack problem)
            Right report -> CliResponse (if null (Deletion.deleteProblems report) then ExitSuccess else ExitFailure 1) (if format == Output.TextFormat then Encoding.encodeUtf8 (renderDelete report) else Output.encodeValue format (deleteValue report)) ""
    Right (ExecuteDelete node confirmation) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        authorized <- maybe (interactiveDelete directory node) (pure . Right . BSC.pack) confirmation
        case authorized of
            Left problem -> pure (failureAs "confirmation_failed" (Text.pack problem))
            Right identifier -> do
                result <- Deletion.executeDelete executable (nativeGit defaultGitExecutable) directory node identifier
                pure $ case result of
                    Left failed@(Deletion.DeleteFailure reason details) -> applicationFailure (Deletion.deleteFailureDiagnostic failed) (Deletion.deleteFailureEvidence failed) reason details
                    Right report -> resultResponse (("deleted", Output.Boolean True) : deleteFields report) ("Deleted local Node branch " <> Text.pack (BSC.unpack (nodeIdBytes (Deletion.deleteNode report))) <> ". Git objects and remote refs were not erased.\n")
    Right (CreateCheckpoint node source contexts) -> do
        loaded <-
            try
                ( case source of
                    InlineMessage text -> pure (Encoding.encodeUtf8 (Text.pack text))
                    FileMessage "-" -> BS.getContents
                    FileMessage path -> BS.readFile path
                )
        case loaded of
            Left problem -> pure (failureAs "message_read_failed" ("Cannot read Checkpoint message: " <> Text.pack (show (problem :: IOException))))
            Right message -> do
                directory <- getCurrentDirectory
                executable <- getExecutablePath
                result <- Checkpoints.checkpoint executable (nativeGit defaultGitExecutable) directory node message contexts
                pure $ case result of
                    Left failed@(Checkpoints.CheckpointFailure reason details) -> applicationFailure (Checkpoints.checkpointFailureDiagnostic failed) (Checkpoints.checkpointFailureEvidence failed) reason details
                    Right value ->
                        CliResponse
                            ExitSuccess
                            ( if format /= Output.TextFormat
                                then Output.encodeValue format (Output.Object [("node", nodeValue (Checkpoints.checkpointNode value)), ("checkpoint", oidValue (Checkpoints.checkpointOid value)), ("predecessor", oidValue (Checkpoints.checkpointPredecessor value)), ("contexts", Output.Array (map oidValue (Checkpoints.checkpointContexts value))), ("diagnostics", Output.Array [Output.diagnostic "multiple_context_versions" "warning" (Text.pack warning) | warning <- Checkpoints.checkpointWarnings value])])
                                else
                                    Encoding.encodeUtf8 $
                                        Text.unlines
                                            ( ["node " <> nodeText (Checkpoints.checkpointNode value), "checkpoint " <> oidText (Checkpoints.checkpointOid value), "predecessor " <> oidText (Checkpoints.checkpointPredecessor value)]
                                                ++ ["context " <> oidText oid | oid <- Checkpoints.checkpointContexts value]
                                            )
                            )
                            (if format == Output.TextFormat then Text.unlines (map ("warning: " <>) (map Text.pack (Checkpoints.checkpointWarnings value))) else "")
    Right (CreateNode path specifiedNode) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        let git = nativeGit defaultGitExecutable
        result <- case specifiedNode of
            Nothing -> Creation.createNode executable git directory path
            Just node -> Creation.createNodeWith (pure node) executable git directory path
        case result of
            Left failed@(Creation.CreationFailure reason details) ->
                pure (applicationFailure (Creation.creationFailureDiagnostic failed) (Creation.creationFailureEvidence failed) reason details)
            Right report -> do
                encoded <- try (Output.renderCreation format report) :: IO (Either IOException BS.ByteString)
                pure $ case encoded of
                    Right bytes -> CliResponse ExitSuccess bytes ""
                    Left problem ->
                        failureAs "output_encoding_failed" ("Node was created, but output encoding failed: " <> Text.pack (show problem) <> ". Inspect the existing Node before retrying.")
    Right UndeployNodes -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        result <- Undeployment.undeploy executable (nativeGit defaultGitExecutable) directory
        pure $ case result of
            Left failed@(Undeployment.UndeploymentFailure reason details) -> applicationFailure (Undeployment.undeploymentFailureDiagnostic failed) (Undeployment.undeploymentFailureEvidence failed) reason details
            Right report ->
                resultResponse
                    [("removed_worktrees", worktreePairs (Undeployment.removedWorktrees report)), ("retained_main_nodes", worktreePairs (Undeployment.retainedMainNodes report))]
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
        case result of
            Left failed@(Deployment.DeploymentFailure reason details) -> pure (applicationFailure (Deployment.deploymentFailureDiagnostic failed) (Deployment.deploymentFailureEvidence failed) reason details)
            Right report -> do
                encoded <- try $ do
                    paths <- if format == Output.TextFormat then pure [] else mapM (\(node, target) -> do bytes <- encodePath target; pure (node, bytes)) (Deployment.deployedWorktrees report)
                    pure $
                        resultResponse
                            [("deployed_worktrees", worktreePairs paths), ("tracking_sources", Output.Array [Output.Object [("node", nodeValue node), ("ref", Output.Bytes ref)] | (node, ref) <- Deployment.trackingSources report])]
                            ( Text.unlines
                                ( ["Deployed " <> decimal (length (Deployment.deployedWorktrees report)) <> " Nodes."]
                                    ++ [nodeText node <> " " <> Text.pack (show target) | (node, target) <- Deployment.deployedWorktrees report]
                                    ++ ["tracking " <> nodeText node <> " " <> Text.pack (show ref) | (node, ref) <- Deployment.trackingSources report]
                                )
                            )
                pure $ case (encoded :: Either IOException CliResponse) of
                    Right response -> response
                    Left problem -> failureAs "output_encoding_failed" ("Deployment completed, but output encoding failed: " <> Text.pack (show problem) <> ". Inspect existing worktrees before retrying.")
  where
    applicationFailure diagnosticValue evidence reason details
        | format == Output.TextFormat = failure 1 (Text.unlines (map Text.pack (reason : details)))
        | Just known <- evidence = CliResponse (ExitFailure 1) (Output.encodeValue format (Output.Object [("success", Output.Boolean False), ("diagnostics", Output.Array [Output.renderDiagnostic diagnosticValue]), ("evidence", Output.evidenceValue known), ("details", Output.Array (map (Output.String . Text.pack) details))])) ""
        | otherwise = diagnosticFailure 1 (Diagnostic.diagnosticCode diagnosticValue) (Text.unlines (map Text.pack (reason : details)))
    failureAs category message = if format == Output.TextFormat then failure 1 message else diagnosticFailure 1 category message
    diagnosticFailure code category message = CliResponse (ExitFailure code) "" (Encoding.decodeUtf8 (Output.encodeValue Output.JsonFormat (Output.diagnostic category "error" message)))
    lifecycle operation message = do
        directory <- getCurrentDirectory
        result <- operation directory
        pure $ either (failureAs "protection_failed" . Text.pack) (const (resultResponse [("enabled", Output.Boolean (message == "Repository protection enabled.\n"))] message)) result
    resultResponse fields text = if format == Output.TextFormat then success text else CliResponse ExitSuccess (Output.encodeValue format (Output.Object fields)) ""
    success output = CliResponse ExitSuccess (Encoding.encodeUtf8 output) ""
    failure code message =
        CliResponse (ExitFailure code) "" $
            if format == Output.TextFormat
                then "git-roam: " <> message <> "\n"
                else Encoding.decodeUtf8 (Output.encodeValue Output.JsonFormat (Output.diagnostic (if code == 2 then "invalid_arguments" else "operation_failed") "error" message))

statusResponse :: Output.OutputFormat -> Status.StatusReport -> CliResponse
statusResponse format report =
    let issues = Status.reportDiagnostics report
     in CliResponse
            (if null issues then ExitSuccess else ExitFailure 3)
            (if format == Output.TextFormat then Encoding.encodeUtf8 (renderStatus report) else Output.encodeValue format (Output.statusValue report))
            (if format == Output.TextFormat then Text.unlines ["git-roam: " <> Status.statusMessage issue | issue <- issues] else "")

checkResponse :: Output.OutputFormat -> Bool -> Check.CheckReport -> CliResponse
checkResponse format showRefs report =
    CliResponse
        (case Check.checkConclusion report of Check.Valid -> ExitSuccess; Check.Invalid -> ExitFailure 1; Check.Inconclusive -> ExitFailure 3)
        (if format == Output.TextFormat then Encoding.encodeUtf8 (Output.renderCheck showRefs report) else Output.encodeValue format (Output.checkValue showRefs report))
        ""
