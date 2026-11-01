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
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Checkpoint as Checkpoints
import qualified GitRoam.Application.Create as Creation
import qualified GitRoam.Application.Delete as Deletion
import qualified GitRoam.Application.Deploy as Deployment
import qualified GitRoam.Application.Discard as Discard
import GitRoam.Application.Inspect
import qualified GitRoam.Application.Protection as Protection
import qualified GitRoam.Application.Undeploy as Undeployment
import GitRoam.BuildInfo (packageVersion)
import GitRoam.Git
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Discard
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects (ObjectProblem (..))
import GitRoam.Protocol.Repository
import System.Directory (getCurrentDirectory)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.IO (hFlush, hIsTerminalDevice, stderr, stdin)

data HelpTopic = GeneralHelp | HelpHelp | VersionHelp | CheckHelp | StatusHelp | EnableHelp | DisableHelp | DeployHelp | UndeployHelp | NodeHelp | NodeCreateHelp | NodeDeleteHelp | CheckpointHelp | DiscardHelp
    deriving (Eq, Show)

data CheckpointMessage = InlineMessage String | FileMessage FilePath deriving (Eq, Show)

data Command = ShowHelp HelpTopic | ShowVersion | CheckNode (Maybe NodeId) | StatusNode (Maybe NodeId) | EnableProtection | DisableProtection | DeployNodes FilePath (Maybe String) | UndeployNodes | CreateNode FilePath | CreateCheckpoint (Maybe NodeId) CheckpointMessage Checkpoints.DependencyEdits | PreviewDiscard [String] | ExecuteDiscard [String] (Maybe String) | PreviewDelete NodeId | ExecuteDelete NodeId (Maybe String)
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
    ["help", "discard"] -> help DiscardHelp
    ["discard", "--help"] -> help DiscardHelp
    ["discard", "-h"] -> help DiscardHelp
    "discard" : args -> discardArgs False Nothing [] args
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
    discardArgs dry confirmation targets args = case args of
        [] | dry && not (null targets) -> Right (PreviewDiscard (reverse targets))
        [] | not dry && not (null targets) -> Right (ExecuteDiscard (reverse targets) confirmation)
        "--dry-run" : rest | not dry && confirmation == Nothing -> discardArgs True confirmation targets rest
        "--confirm" : value : rest | not dry && confirmation == Nothing && length value == 64 && all (`elem` ("0123456789abcdef" :: String)) value -> discardArgs False (Just value) targets rest
        value : rest | validValue value -> discardArgs dry confirmation (value : targets) rest
        _ -> Left "Usage: git roam discard [--dry-run | --confirm <plan-id>] <ref-or-oid>..."
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
            , "  node delete     Explicitly delete an unchecked-out, unreferenced Node"
            , "  checkpoint      Confirm committed Content and complete dependencies"
            , "  discard         Preview or explicitly confirm Checkpoint discard"
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
    NodeHelp -> Text.unlines ["usage: git roam node <command>", "", "Commands:", "  create --path <path>  Create a UUIDv4 Node with an editable linked worktree", "  delete --node <uuid>  Preview or confirm non-cascading Node deletion"]
    NodeDeleteHelp -> Text.unlines ["usage: git roam node delete --node <uuid> [--dry-run | --confirm <plan-id>]", "", "Preview removal of the explicit local UUID branch and its reviewed local branch configuration.", "Every other Node's retained historical dependency is checked; incoming edges block deletion.", "Any main or linked worktree checking out this branch blocks deletion; no implicit undeploy.", "--dry-run is read-only. Execution requires enabled protection and the complete plan ID.", "Without --confirm, terminal input/stderr are required to review and type the plan ID.", "No cascade, force, object erasure or recovery guarantee; remote refs and other Nodes are retained.", "A later deploy may recreate the Node from fetched remote candidates."]
    NodeCreateHelp -> Text.unlines ["usage: git roam node create --path <path>", "", "Create a UUIDv4 identity, empty-marker Root, persistent local branch and linked worktree.", "Requires enabled matching protection and valid managed history. Uses native Git author/committer configuration.", "Reports UUID, Root OID and actual path; existing Nodes are not deployed or advanced.", "Failures compensate only proven new unchanged state; user changes and uncertain results are retained."]
    CheckpointHelp -> Text.unlines ["usage: git roam checkpoint [--node <uuid>] (-m <text> | -F <file>)", "       [--depend <ref-or-oid>] [--drop-dependency <uuid>] [--clear-dependencies]", "", "Select an explicit Node or infer its worktree; Root requires committed Content first.", "Messages must be nonempty UTF-8 text without NUL. -F - reads stdin; no editor is started.", "Inherit the previous full dependency set; --depend adds/replaces one external Checkpoint per UUID.", "Dependencies accept Git refs and unambiguous commit OIDs, including abbreviations; no revision expressions.", "Repeat --depend/--drop-dependency for different Nodes. Clear may combine with additions, not removals.", "Conflicting edits, self dependencies and unretained/non-Checkpoint inputs are refused.", "Uses the committed tree, preserving all Content history and uncommitted index/worktree data."]
    DiscardHelp -> Text.unlines ["usage: git roam discard --dry-run <ref-or-oid>...", "       git roam discard --confirm <plan-id> <ref-or-oid>...", "       git roam discard <ref-or-oid>...", "", "Preview the exact minimal successor closure, old/new tips, Content loss and affected worktrees.", "Refs or unambiguous commit OIDs must identify currently retained Checkpoints.", "--dry-run is read-only and prints a plan ID only when all preconditions pass.", "Execution requires matching enabled protection and confirmation of that complete plan ID.", "Without --confirm, terminal input/stderr are required: review the preview and type its plan ID.", "Stale plans, multiple remaining maxima and unsafe worktrees refuse; there is no force option.", "Affected clean linked worktrees are recreated at their original paths around one ref transaction.", "Main/nested target worktrees and private worktree configuration/refs require prior manual handling.", "Failures report actual state; committed discards are never rolled back and recovery is not promised."]
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

renderDiscard :: Discard.DiscardPreview -> Text
renderDiscard preview =
    Text.unlines $
        ["Read-only Checkpoint discard preview; no changes were made."]
            ++ ["plan " <> Text.pack (BSC.unpack identifier) | Just identifier <- [Discard.previewPlanId preview]]
            ++ ["target " <> oid value | value <- Set.toList (discardTargets impact)]
            ++ concat
                [ ["discard " <> oid value] ++ map reason (Set.toList causes)
                | (value, causes) <- Map.toList (discardReasons impact)
                ]
            ++ concatMap node (discardNodes impact)
            ++ ["worktree " <> maybe "unknown" uuid (Worktrees.worktreeNode record) <> " " <> Text.pack (show (Worktrees.treePath record)) <> if Worktrees.treeMain record then " (main)" else " (linked)" | record <- Discard.previewWorktrees preview]
            ++ ["Affected linked worktrees will be recreated at the same paths with fresh Git administration." | any (not . Worktrees.treeMain) (Discard.previewWorktrees preview)]
            ++ ["blocked " <> Text.pack problem | problem <- Discard.previewProblems preview]
            ++ [if null (Discard.previewProblems preview) then "Preview complete. Execution requires explicit confirmation of this plan ID; recovery is not guaranteed." else "Preview blocked. No executable candidate is authorized."]
  where
    impact = Discard.previewImpact preview
    oid = Text.pack . BSC.unpack . objectIdBytes
    uuid = Text.pack . BSC.unpack . nodeIdBytes
    reason ExplicitTarget = "  reason explicitly requested"
    reason (FormalSuccessor parent) = "  reason formal-history successor of " <> oid parent
    reason (DependencySuccessor parent) = "  reason depends on " <> oid parent
    node change =
        [ "node " <> uuid (discardNode change)
        , "  old " <> oid (discardOldTip change)
        , "  new " <> maybe "unrepresentable" (\value -> oid value <> if Set.null (discardRemainingMaxima change) then " (Root)" else "") (discardNewTip change)
        , "  Checkpoints to discard: " <> Text.pack (show (Set.size (discardNodeVersions change)))
        ]
            ++ ["  checkpoint " <> oid value | value <- Set.toList (discardNodeVersions change)]
            ++ ["  remaining maximum " <> oid value | value <- Set.toList (discardRemainingMaxima change)]
            ++ case discardLostContent change of
                Nothing -> ["  Content impact unavailable: remaining formal history is not representable."]
                Just values -> ["  Content commits losing managed entry: " <> Text.pack (show (Set.size values))] ++ ["  content " <> oid value | value <- Set.toList values]

interactiveDiscard :: FilePath -> [String] -> IO (Either String BS.ByteString)
interactiveDiscard directory references = do
    outcome <- try $ do
        inputTerminal <- hIsTerminalDevice stdin
        outputTerminal <- hIsTerminalDevice stderr
        if not (inputTerminal && outputTerminal)
            then pure (Left "Noninteractive discard requires --dry-run review followed by --confirm <plan-id>")
            else do
                outcome <- Discard.previewDiscard (nativeGit defaultGitExecutable) directory references
                case outcome of
                    Left problem -> pure (Left problem)
                    Right preview -> do
                        BS.hPut stderr (Encoding.encodeUtf8 (renderDiscard preview))
                        case Discard.previewPlanId preview of
                            Nothing -> pure (Left "Discard preview is blocked")
                            Just identifier -> do
                                BSC.hPutStr stderr "Type this plan ID to discard: "
                                hFlush stderr
                                answer <- BSC.hGetLine stdin
                                pure (if answer == identifier then Right identifier else Left "Discard confirmation declined; no changes were made")
    pure $ either (Left . show) id (outcome :: Either IOException (Either String BS.ByteString))

renderDelete :: Deletion.DeletePreview -> Text
renderDelete report =
    Text.unlines $
        [ "Read-only Node deletion preview; no changes were made."
        , "node " <> node (Deletion.deleteNode report)
        , "old " <> oid (Deletion.deleteOldTip report)
        , "root " <> oid (Deletion.deleteRoot report)
        ]
            ++ ["plan " <> Text.pack (BSC.unpack identifier) | Just identifier <- [Deletion.deletePlanId report]]
            ++ ["withdraw checkpoint " <> oid value | value <- Set.toList (Deletion.deleteVersions report)]
            ++ ["lose managed Content entry " <> oid value | value <- Set.toList (Deletion.deleteContent report)]
            ++ ["incoming " <> node other <> " " <> oid from <> " depends on " <> oid required | (other, from, required) <- Deletion.deleteIncoming report]
            ++ ["checked out " <> Text.pack (show (Worktrees.treePath record)) <> if Worktrees.treeMain record then " (main)" else " (linked)" | record <- Deletion.deleteWorktrees report]
            ++ ["remove local config " <> Text.pack (BSC.unpack key) | key <- Deletion.deleteConfigKeys report]
            ++ ["blocked " <> Text.pack problem | problem <- Deletion.deleteProblems report]
            ++ ["No cascading removal, object erasure or recovery guarantee. Remote refs remain; deploy may recreate this Node."]
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
    Right (PreviewDelete node) -> do
        directory <- getCurrentDirectory
        result <- Deletion.previewDelete (nativeGit defaultGitExecutable) directory node
        pure $ case result of
            Left problem -> failure 1 (Text.pack problem)
            Right report -> CliResponse (if null (Deletion.deleteProblems report) then ExitSuccess else ExitFailure 1) (renderDelete report) ""
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
    Right (PreviewDiscard references) -> do
        directory <- getCurrentDirectory
        result <- Discard.previewDiscard (nativeGit defaultGitExecutable) directory references
        pure $ case result of
            Left problem -> failure 1 (Text.pack problem)
            Right preview -> CliResponse (if null (Discard.previewProblems preview) then ExitSuccess else ExitFailure 1) (renderDiscard preview) (if null (Discard.previewProblems preview) then "" else "git-roam: discard preview is blocked; no changes were made.\n")
    Right (ExecuteDiscard references confirmation) -> do
        directory <- getCurrentDirectory
        executable <- getExecutablePath
        authorized <- case confirmation of
            Just identifier -> pure (Right (BSC.pack identifier))
            Nothing -> interactiveDiscard directory references
        case authorized of
            Left problem -> pure (failure 1 (Text.pack problem))
            Right identifier -> do
                outcome <- Discard.executeDiscard executable (nativeGit defaultGitExecutable) directory references identifier
                pure $ case outcome of
                    Left (Discard.DiscardFailure reason details) -> failure 1 (Text.unlines (map Text.pack (reason : details)))
                    Right result -> success (Text.unlines (["Discarded " <> decimal (Set.size (Discard.resultDiscarded result)) <> " Checkpoints.", "plan " <> Text.pack (BSC.unpack (Discard.resultPlanId result))] ++ ["node " <> nodeText node <> " " <> oidText oid | (node, oid) <- Map.toList (Discard.resultRefs result)] ++ ["restored " <> Text.pack (show (Worktrees.treePath r)) | r <- Discard.resultWorktrees result]))
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
