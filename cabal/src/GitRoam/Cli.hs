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
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Checkpoint as Checkpoints
import qualified GitRoam.Application.Create as Creation
import qualified GitRoam.Application.Delete as Deletion
import qualified GitRoam.Application.Deploy as Deployment
import GitRoam.Application.Inspect
import qualified GitRoam.Application.Protection as Protection
import qualified GitRoam.Application.Undeploy as Undeployment
import GitRoam.BuildInfo (packageVersion)
import GitRoam.Git
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import qualified GitRoam.Output as Output
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (ObjectProblem (..))
import GitRoam.Protocol.Repository
import System.Directory (getCurrentDirectory)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute)
import System.IO (hFlush, hIsTerminalDevice, stderr, stdin)

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp | CheckHelp | StatusHelp | EnableHelp | DisableHelp | DeployHelp | UndeployHelp | NodeHelp | NodeCreateHelp | NodeDeleteHelp | CheckpointHelp
    deriving (Eq, Show)

data CheckpointMessage = InlineMessage String | FileMessage FilePath deriving (Eq, Show)

data Command = ShowHelp HelpTopic | ShowVersion | CheckNode (Maybe NodeId) | StatusNode (Maybe NodeId) | EnableProtection | DisableProtection | DeployNodes FilePath (Maybe String) | UndeployNodes | CreateNode FilePath (Maybe NodeId) Output.OutputFormat | CreateCheckpoint (Maybe NodeId) CheckpointMessage [String] | PreviewDelete NodeId | ExecuteDelete NodeId (Maybe String)
    deriving (Eq, Show)

data CliResponse = CliResponse
    { responseExitCode :: ExitCode
    , responseStdout :: BS.ByteString
    , responseStderr :: Text
    }
    deriving (Eq, Show)

parseCommand :: [String] -> Either Text Command
parseCommand arguments = do
    (deployment, remaining) <- parseTopLevel arguments
    parseSubcommand deployment remaining

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
    "node" : "create" : args -> createArgs Nothing Nothing Nothing args
    "node" : _ -> Left "Usage: git roam node create --path <path> [--id <uuid>] [--format text|json|cbor]"
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
    createArgs path node format args = case args of
        [] -> CreateNode <$> deploymentPath path <*> pure node <*> pure (maybe Output.TextFormat id format)
        "--path" : value : rest | path == Nothing && validValue value -> createArgs (Just value) node format rest
        "--id" : value : rest | node == Nothing -> uuid value >>= \selected -> createArgs path (Just selected) format rest
        "--format" : value : rest | format == Nothing -> do
            selected <- case value of
                "text" -> Right Output.TextFormat
                "json" -> Right Output.JsonFormat
                "cbor" -> Right Output.CborFormat
                _ -> Left "Unknown output format (expected text, json, or cbor)"
            createArgs path node (Just selected) rest
        _ -> Left "Usage: git roam node create --path <path> [--id <uuid>] [--format text|json|cbor]"
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
            [ "usage: git roam [--deploy-path <absolute-path>] <command> [options]"
            , ""
            , "Commands:"
            , "  help [command]  Show general or command-specific help"
            , "  version         Print the package version"
            , "  check           Validate Node history and recorded contexts"
            , "  status          Show Node history, Checkpoint contexts and worktrees"
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
            , "  --deploy-path <absolute-path>"
            , "                  Deployment root for node create/deploy; mutually exclusive with --path"
            , "                  Place before the command; other commands do not use the directory"
            ]
    HelpHelp -> Text.unlines ["usage: git roam help [command]", "", "Show general help or help for an available command."]
    VersionHelp -> Text.unlines ["usage: git roam version", "       git roam --version", "", "Print the package version."]
    CheckHelp -> inspectionHelp "check" "Validate the complete protocol history reachable from the selected managed Node refs."
    StatusHelp -> inspectionHelp "status" "Show Node history, the latest Checkpoint's direct contexts, worktrees and diagnostics."
    EnableHelp -> Text.unlines ["usage: git roam enable", "", "Install or validate the repository-local reference-transaction Hook.", "The Hook runs git-roam --reference-transaction from Git's PATH, not a pinned executable path.", "An existing canonical Hook is unchanged; recognized old absolute-path Git-roam Hooks are migrated.", "Incomplete, inherited or divergent configuration is refused; Node history is not changed."]
    DisableHelp -> Text.unlines ["usage: git roam disable", "", "Remove Git-roam protection after all Node linked worktrees have been undeployed."]
    DeployHelp -> Text.unlines ["usage: git roam deploy --path <path> [--remote <remote>]", "       git roam --deploy-path <absolute-path> deploy [--remote <remote>]", "", "Provide exactly one path source; top-level --deploy-path and subcommand --path are mutually exclusive.", "Deploy all local Nodes and canonical fetched candidates under eight-character UUID directories.", "--remote limits discovery of missing Nodes to that remote; local branches are never advanced.", "Requires enabled protection. Does not fetch, merge or relocate existing worktrees.", "Failures report residual state after conservative compensation; no filesystem atomicity is promised."]
    UndeployHelp -> Text.unlines ["usage: git roam undeploy", "", "Remove all Node linked worktrees, including manually created or moved ones.", "Requires enabled protection and valid managed history. Every target is preflighted before removal.", "Retains branches, history, protection and main/detached/unmanaged worktrees.", "No subset, path, force or automatic rollback; partial failures report actual remaining state."]
    NodeHelp -> Text.unlines ["usage: git roam node <command>", "", "Commands:", "  create [--path <path>] [--id <uuid>] [--format text|json|cbor]  Create a Node with an editable linked worktree", "    Requires subcommand --path or top-level --deploy-path, not both.", "  delete --node <uuid>  Preview or confirm non-cascading Node deletion"]
    NodeDeleteHelp -> Text.unlines ["usage: git roam node delete --node <uuid> [--dry-run | --confirm <plan-id>]", "", "Preview removal of the explicit local UUID branch and its reviewed local branch configuration.", "Deletion does not cascade into other Nodes whose history records contexts from this Node.", "The preview lists commits that become unreachable from the remaining managed refs; Git objects are not erased.", "Any main or linked worktree checking out this branch blocks deletion; no implicit undeploy.", "--dry-run is read-only. Execution requires enabled protection and the complete plan ID.", "Without --confirm, terminal input/stderr are required to review and type the plan ID.", "No cascade, force, object erasure or recovery guarantee; remote refs and other Nodes are retained.", "A later deploy may recreate the Node from fetched remote candidates."]
    NodeCreateHelp -> Text.unlines ["usage: git roam node create --path <path> [--id <uuid>] [--format text|json|cbor]", "       git roam --deploy-path <absolute-path> node create [--id <uuid>] [--format text|json|cbor]", "", "Provide exactly one path source; top-level --deploy-path and subcommand --path are mutually exclusive.", "Create an identity, empty-marker Root, persistent local branch and linked worktree.", "--id accepts UUIDv4, Nil UUID or Max UUID; without it, a fresh UUIDv4 is generated.", "--format text (default) preserves the existing output; json and cbor provide structured machine output.", "JSON paths contain UTF-8 text when valid plus a lossless Base64 byte representation; CBOR paths are byte strings.", "Requires enabled matching protection and valid managed history. Uses native Git author/committer configuration.", "Reports UUID, Root OID, actual worktree path and UUID bundle path; existing Nodes are not deployed or advanced.", "Failures compensate only proven new unchanged state; user changes and uncertain results are retained."]
    CheckpointHelp -> Text.unlines ["usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>)", "       --context <revision> [--context <revision> ...]", "", "Select an explicit Node or infer it from the current Node worktree. A Checkpoint may directly follow Root.", "Messages must be nonempty UTF-8 text without NUL. -F - reads stdin; no editor is started.", "Each --context selects one external commit parent; argument order determines parent order.", "Contexts accept Git refs and unambiguous commit OIDs, including abbreviations; no revision expressions.", "A context may be a Root, Content or Checkpoint and need not be retained by its Node's current branch.", "Duplicate context OIDs and contexts belonging to the target Node are refused.", "Multiple distinct contexts from one external Node are accepted with a compatibility warning.", "Uses the current committed tree, preserving uncommitted index/worktree data."]
  where
    inspectionHelp command description =
        Text.unlines
            [ "usage: git roam " <> command <> " [--node <uuid>]"
            , ""
            , description
            , "Select an explicit Node, infer the current Node worktree, or inspect the repository."
            , "A selected Node is validated through its complete Git parent ancestry; other local Node branches are not required."
            , "Read-only; repository protection need not be enabled."
            ]

renderDelete :: Deletion.DeletePreview -> Text
renderDelete report =
    Text.unlines $
        [ "Read-only Node deletion preview; no changes were made."
        , "node " <> node (Deletion.deleteNode report)
        , "old " <> oid (Deletion.deleteOldTip report)
        , "root " <> oid (Deletion.deleteRoot report)
        ]
            ++ ["plan " <> Text.pack (BSC.unpack identifier) | Just identifier <- [Deletion.deletePlanId report]]
            ++ ["exclusive commit " <> oid value | value <- Set.toList (Deletion.deleteExclusiveCommits report)]
            ++ ["checked out " <> Text.pack (show (Worktrees.treePath record)) <> if Worktrees.treeMain record then " (main)" else " (linked)" | record <- Deletion.deleteWorktrees report]
            ++ ["remove local config " <> Text.pack (BSC.unpack key) | key <- Deletion.deleteConfigKeys report]
            ++ ["blocked " <> Text.pack problem | problem <- Deletion.deleteProblems report]
            ++ ["Exclusive commits are not erased; they are unreachable from the remaining managed refs at this observation.", "No cascading removal, object erasure or recovery guarantee. Remote refs remain; deploy may recreate this Node."]
  where
    node = Text.pack . BSC.unpack . nodeIdBytes
    oid = Text.pack . BSC.unpack . objectIdBytes

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

-- Internal Hook dispatch is independent of public deployment-path validation.
-- A PATH wrapper can prepend the option, but the Hook never reads its value.
referenceTransactionPhase :: [String] -> Maybe String
referenceTransactionPhase ["--reference-transaction", phase]
    | phase `elem` ["preparing", "prepared", "committed", "aborted"] = Just phase
referenceTransactionPhase ("--deploy-path" : _ : remaining) = referenceTransactionPhase remaining
referenceTransactionPhase _ = Nothing

runCli :: [String] -> IO CliResponse
runCli arguments = case referenceTransactionPhase arguments of
    Just phase -> do
        directory <- getCurrentDirectory
        input <- BSC.getContents
        result <- Protection.evaluateTransaction directory phase input
        pure $ case result of
            Right () -> CliResponse ExitSuccess "" ""
            Left problem -> CliResponse (ExitFailure 1) "" ("git-roam: reference update refused: " <> Text.pack problem <> "\n")
    Nothing -> runParsedCommand (parseCommand arguments)

runParsedCommand :: Either Text Command -> IO CliResponse
runParsedCommand parsed = case parsed of
    Left message -> pure (failure 2 (message <> "\nTry 'git roam --help' for usage."))
    Right (ShowVersion) -> pure (success ("git-roam " <> Text.pack packageVersion <> "\n"))
    Right (ShowHelp topic) -> pure (success (renderHelp topic))
    Right (CheckNode node) -> inspect False node
    Right (StatusNode node) -> inspect True node
    Right EnableProtection -> lifecycle Protection.enableProtection "Repository protection enabled.\n"
    Right DisableProtection -> lifecycle Protection.disableProtection "Repository protection disabled.\n"
    Right (PreviewDelete node) -> do
        directory <- getCurrentDirectory
        result <- Deletion.previewDelete (nativeGit defaultGitExecutable) directory node
        pure $ case result of
            Left problem -> failure 1 (Text.pack problem)
            Right report -> CliResponse (if null (Deletion.deleteProblems report) then ExitSuccess else ExitFailure 1) (Encoding.encodeUtf8 (renderDelete report)) ""
    Right (ExecuteDelete node confirmation) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        authorized <- maybe (interactiveDelete directory node) (pure . Right . BSC.pack) confirmation
        case authorized of
            Left problem -> pure (failure 1 (Text.pack problem))
            Right identifier -> do
                result <- Deletion.executeDelete executable (nativeGit defaultGitExecutable) directory node identifier
                pure $ case result of
                    Left (Deletion.DeleteFailure reason details) -> failure 1 (Text.unlines (map Text.pack (reason : details)))
                    Right report -> success ("Deleted local Node branch " <> Text.pack (BSC.unpack (nodeIdBytes (Deletion.deleteNode report))) <> ". Git objects and remote refs were not erased.\n")
    Right (CreateCheckpoint node source contexts) -> do
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
                result <- Checkpoints.checkpoint executable (nativeGit defaultGitExecutable) directory node message contexts
                pure $ case result of
                    Left (Checkpoints.CheckpointFailure reason details) -> failure 1 (Text.unlines (Text.pack reason : map Text.pack details))
                    Right value ->
                        CliResponse
                            ExitSuccess
                            ( Encoding.encodeUtf8 $
                                Text.unlines
                                    ( ["node " <> nodeText (Checkpoints.checkpointNode value), "checkpoint " <> oidText (Checkpoints.checkpointOid value), "predecessor " <> oidText (Checkpoints.checkpointPredecessor value)]
                                        ++ ["context " <> oidText oid | oid <- Checkpoints.checkpointContexts value]
                                    )
                            )
                            (Text.unlines (map ("warning: " <>) (map Text.pack (Checkpoints.checkpointWarnings value))))
    Right (CreateNode path specifiedNode format) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        let git = nativeGit defaultGitExecutable
        result <- case specifiedNode of
            Nothing -> Creation.createNode executable git directory path
            Just node -> Creation.createNodeWith (pure node) executable git directory path
        case result of
            Left (Creation.CreationFailure reason details) ->
                pure (failure 1 (Text.unlines (Text.pack reason : map Text.pack details)))
            Right report -> do
                encoded <- try (Output.renderCreation format report) :: IO (Either IOException BS.ByteString)
                pure $ case encoded of
                    Right bytes -> CliResponse ExitSuccess bytes ""
                    Left problem ->
                        failure 1 ("Node was created, but output encoding failed: " <> Text.pack (show problem) <> ". Inspect the existing Node before retrying.")
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
                                    then "OK: " <> decimal (length (reportNodes report)) <> " Nodes; histories and recorded contexts are valid.\n"
                                    else ""
                    errors = Text.concat ["git-roam: " <> stateDiagnostic issue <> "\n" | issue <- issues]
                 in CliResponse (if null issues then ExitSuccess else ExitFailure 1) (Encoding.encodeUtf8 output) errors
    success output = CliResponse ExitSuccess (Encoding.encodeUtf8 output) ""
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
            , "  content-tail " <> (case viewKind node of Content _ -> "yes"; _ -> "no")
            , "  checkpoints " <> decimal (viewCheckpointCount node)
            , "  contexts " <> (if null (viewContextParents node) then "none" else "")
            ]
                ++ ["    " <> oidText oid | oid <- viewContextParents node]
                ++ [ "  worktree " <> Text.pack (show (worktreePath worktree)) <> if worktreeIsMain worktree then " (main; not a removable deployment)" else " (linked)"
                   | worktree <- reportWorktrees report
                   , worktreeNode worktree == Just (viewNode node)
                   ]
    kind Root = "root"
    kind (Content _) = "content"
    kind (Checkpoint _ _) = "checkpoint"
