{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Status (
    NodeProperty (..),
    NodeSelection (..),
    PropertySelection (..),
    StatusQuery (..),
    PropertyResult (..),
    NodeStatus (..),
    RemoteObservation (..),
    UpstreamObservation (..),
    StatusReport (..),
    StatusDiagnostic (..),
    queryStatus,
    selectedProperties,
    propertyName,
    reportDiagnostics,
) where

import Control.Applicative ((<|>))
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import GitRoam.Application.Protection (ProtectionState, observeProtection)
import GitRoam.Git
import qualified GitRoam.Git.Commit as Commit
import GitRoam.Git.Objects (readOnlyEnvironment)
import qualified GitRoam.Git.Refs as Refs
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Repository
import System.Exit (ExitCode (..))

-- Working-tree file status is added separately from registered worktrees.
data NodeProperty = TipProperty | CommitProperty | WorktreesProperty | RemoteProperty deriving (Eq, Ord, Show)
data NodeSelection = AllNodes | SelectedNodes (Set.Set NodeId) deriving (Eq, Show)
data PropertySelection = DefaultProperties | SelectedProperties (Set.Set NodeProperty) deriving (Eq, Show)
data StatusQuery = RepositoryStatus | NodeStatusQuery NodeSelection PropertySelection deriving (Eq, Show)
data PropertyResult a = NotRequested | Unavailable | Available a deriving (Eq, Show)
data UpstreamObservation = UpstreamObservation
    { upstreamRemote :: Maybe BS.ByteString
    , upstreamSource :: Maybe BS.ByteString
    , upstreamRef :: Maybe BS.ByteString
    }
    deriving (Eq, Show)
data RemoteObservation = RemoteObservation
    { remoteUpstream :: PropertyResult (Maybe UpstreamObservation)
    , remoteRefs :: Maybe [(BS.ByteString, ObjectId)]
    }
    deriving (Eq, Show)
data NodeStatus = NodeStatus
    { statusNode :: NodeId
    , statusTip :: PropertyResult ObjectId
    , statusCommit :: PropertyResult Commit.CommitMetadata
    , statusWorktrees :: PropertyResult [Worktrees.Worktree]
    , statusRemote :: PropertyResult RemoteObservation
    }
    deriving (Eq, Show)
data StatusDiagnostic = StatusDiagnostic
    { statusCode :: Text
    , statusMessage :: Text
    , diagnosticNode :: Maybe NodeId
    , diagnosticProperty :: Maybe NodeProperty
    , diagnosticPath :: Maybe BS.ByteString
    }
    deriving (Eq, Ord, Show)
data StatusReport = RepositoryReport ProtectionState [StatusDiagnostic] | NodesReport [NodeStatus] [StatusDiagnostic] deriving (Eq, Show)

reportDiagnostics :: StatusReport -> [StatusDiagnostic]
reportDiagnostics (RepositoryReport _ issues) = issues
reportDiagnostics (NodesReport _ issues) = issues

selectedProperties :: PropertySelection -> Set.Set NodeProperty
selectedProperties DefaultProperties = Set.fromList [TipProperty, WorktreesProperty, RemoteProperty]
selectedProperties (SelectedProperties values) = values

propertyName :: NodeProperty -> Text
propertyName TipProperty = "tip"
propertyName CommitProperty = "commit"
propertyName WorktreesProperty = "worktrees"
propertyName RemoteProperty = "remote"

queryStatus :: Git IO -> FilePath -> StatusQuery -> IO (Either RepositoryError StatusReport)
queryStatus git directory request = do
    discovered <- inspectRepository safeGit directory readOnlyEnvironment
    case discovered of
        Left problem -> pure (Left problem)
        Right repository ->
            Right <$> case request of
                RepositoryStatus -> do
                    (state, problem) <- observeProtection safeGit directory
                    pure (RepositoryReport state [issue "protection_unavailable" Nothing Nothing message | message <- maybe [] pure problem])
                NodeStatusQuery selection properties -> nodes repository selection (selectedProperties properties)
  where
    environment = readOnlyEnvironment ++ [(key, Nothing) | key <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]
    safeGit = withGitEnvironment environment git
    issue code node property message = StatusDiagnostic code (Text.pack message) node property Nothing
    nodes repository selection properties = do
        let format = repositoryObjectFormat repository
            wants property = Set.member property properties
            scope = if wants RemoteProperty then Refs.LocalAndRemoteUpstreams else Refs.LocalNodes
        (before, upstreamBeforeErrors) <- observeRefs format scope
        let localRefs = Map.fromList [(Refs.observedNode ref, ref) | ref <- Refs.observationRefs before, Refs.observedRemotePrefix ref == Nothing]
            chosen = case selection of AllNodes -> Map.keys localRefs; SelectedNodes values -> Set.toAscList values
        commitObservation <-
            if wants CommitProperty
                then Commit.readCommitMetadata safeGit directory format environment [Refs.observedTip ref | node <- chosen, Just ref <- [Map.lookup node localRefs], BS.null (Refs.observedSymbolic ref)]
                else pure (Commit.CommitObservation Map.empty [])
        trees <- if wants WorktreesProperty then Just <$> Worktrees.listWorktrees safeGit directory format else pure Nothing
        configs <- if wants RemoteProperty then Just <$> Refs.readUpstreamConfig safeGit directory environment else pure Nothing
        (after, upstreamAfterErrors) <- observeRefs format scope
        let commits = Commit.observedCommits commitObservation
            commitSessions = [issue "commit_session_incomplete" Nothing (Just CommitProperty) ("Raw commit metadata session did not finish successfully: " ++ show (Commit.commitSessionProblems commitObservation)) | not (null (Commit.commitSessionProblems commitObservation))]
            chosenSet = Set.fromList chosen
            registered = case trees of
                Just (Right records) -> Just (Map.map reverse (Map.fromListWith (++) [(node, [tree]) | tree <- records, Just node <- [Worktrees.worktreeNode tree]]))
                _ -> Nothing
            remoteCandidates = [ref | ref <- Refs.observationRefs before, Refs.observedRemotePrefix ref /= Nothing]
            tracking = Map.map reverse (Map.fromListWith (++) [(Refs.observedNode ref, [(Refs.observedRef ref, Refs.observedTip ref)]) | ref <- remoteCandidates, BS.null (Refs.observedSymbolic ref)])
            symbolicNodes = Set.fromList [Refs.observedNode ref | ref <- remoteCandidates, Set.member (Refs.observedNode ref) chosenSet, not (BS.null (Refs.observedSymbolic ref))]
            remoteTips node =
                let refs = Map.findWithDefault [] node tracking
                 in if not (null refs) || (Refs.observationComplete before && Set.notMember node symbolicNodes) then Just refs else Nothing
            build node =
                let found = Map.lookup node localRefs
                    (upstream, upstreamIssues) = upstreamFor node found configs
                    row =
                        NodeStatus
                            node
                            (if not (wants TipProperty) then NotRequested else case found of Just ref | BS.null (Refs.observedSymbolic ref) -> Available (Refs.observedTip ref); _ -> Unavailable)
                            (if not (wants CommitProperty) then NotRequested else case found of Just ref | BS.null (Refs.observedSymbolic ref), Just (Right value) <- Map.lookup (Refs.observedTip ref) commits -> Available value; _ -> Unavailable)
                            (if not (wants WorktreesProperty) then NotRequested else maybe Unavailable (Available . Map.findWithDefault [] node) registered)
                            (if not (wants RemoteProperty) then NotRequested else Available (RemoteObservation upstream (remoteTips node)))
                    missing = case found of
                        Nothing -> [issue (if Refs.observationComplete before then "node_not_found" else "node_unavailable") (Just node) Nothing "No reliable local Node ref was observed"]
                        Just ref | not (BS.null (Refs.observedSymbolic ref)) -> [issue "symbolic_node_branch" (Just node) Nothing "The Node branch is symbolic"]
                        _ -> []
                    commitIssues = [issue "commit_unavailable" (Just node) (Just CommitProperty) (show problem) | wants CommitProperty, Just ref <- [found], BS.null (Refs.observedSymbolic ref), Just (Left problem) <- [Map.lookup (Refs.observedTip ref) commits]]
                 in (row, missing ++ commitIssues ++ [value | wants RemoteProperty, value <- upstreamIssues])
            rows = map build chosen
            fingerprint observed = Map.fromList [(Refs.observedRef ref, (Refs.observedTip ref, Refs.observedSymbolic ref)) | ref <- Refs.observationRefs observed]
            upstreamFingerprint observed = Map.fromList [(Refs.observedRef ref, (Refs.observedUpstream ref, Refs.observedUpstreamRemote ref)) | ref <- Refs.observationRefs observed]
            upstreamChanged = null upstreamBeforeErrors && null upstreamAfterErrors && upstreamFingerprint before /= upstreamFingerprint after
            changed = [issue "observation_changed" Nothing Nothing "Refs changed during the query; results are not a consistent snapshot" | fingerprint before /= fingerprint after || upstreamChanged]
            refIssues = map refIssue (Refs.observationErrors before ++ Refs.observationErrors after)
            treeIssues = case trees of Just (Left problem) -> [issue "worktrees_unavailable" Nothing (Just WorktreesProperty) problem]; _ -> []
            configIssues = case configs of
                Nothing -> []
                Just observed ->
                    [ issue (if Refs.configProblemNode problem == Nothing then "upstream_unavailable" else "upstream_config_invalid") (Refs.configProblemNode problem) (Just RemoteProperty) (Refs.configProblemMessage problem)
                    | problem <- Refs.configProblems observed
                    , maybe True (`Set.member` chosenSet) (Refs.configProblemNode problem)
                    ]
            upstreamReadIssues = [issue "upstream_unavailable" Nothing (Just RemoteProperty) (Text.unpack (statusMessage (refIssue problem))) | problem <- upstreamBeforeErrors ++ upstreamAfterErrors]
            symbolicRemote = [issue "symbolic_remote_ref" (Just (Refs.observedNode ref)) (Just RemoteProperty) "A remote Node candidate is symbolic" | ref <- remoteCandidates, Set.member (Refs.observedNode ref) chosenSet, not (BS.null (Refs.observedSymbolic ref))]
        pure (NodesReport (map fst rows) (deduplicate (refIssues ++ treeIssues ++ configIssues ++ upstreamReadIssues ++ symbolicRemote ++ concatMap snd rows ++ commitSessions ++ changed)))
    -- The optional atom can fail on branch configuration even when plain refs
    -- remain readable. Keep its failure separate, and never trust failed stdout.
    observeRefs format scope = do
        observed <- Refs.readNodeRefs safeGit directory environment format scope
        if scope == Refs.LocalAndRemoteUpstreams && any processFailure (Refs.observationErrors observed)
            then do
                basic <- Refs.readNodeRefs safeGit directory environment format Refs.LocalAndRemoteNodes
                pure (basic, Refs.observationErrors observed)
            else pure (observed, [])
    processFailure (Refs.RefTransportFailure _) = True
    processFailure (Refs.RefCommandFailure result) = gitExitCode result /= ExitSuccess
    processFailure _ = False
    upstreamFor node found configs = case configs of
        Nothing -> (Unavailable, [])
        Just observed
            | any (\problem -> maybe True (== node) (Refs.configProblemNode problem)) (Refs.configProblems observed) -> (Unavailable, [])
            | otherwise -> case Map.lookup node (Refs.observedConfigs observed) of
                Nothing -> (Available Nothing, [])
                Just config | null (Refs.upstreamSources config) -> (Available Nothing, [])
                Just config ->
                    let remote = (found >>= Refs.observedUpstreamRemote) <|> effective (Refs.upstreamRemotes config)
                        source = single (Refs.upstreamSources config)
                        multiple = length (Refs.upstreamSources config) > 1
                        resolved = if not multiple && source /= Nothing && remote /= Nothing then found >>= Refs.observedUpstream else Nothing
                        issues =
                            [issue "upstream_ambiguous" (Just node) (Just RemoteProperty) "Multiple merge entries cannot be represented as a single upstream" | multiple]
                                ++ [issue "upstream_unresolved" (Just node) (Just RemoteProperty) "Configured upstream cannot be resolved to a single local ref" | not multiple && (source == Nothing || remote == Nothing || resolved == Nothing)]
                     in (Available (Just (UpstreamObservation remote source resolved)), issues)
    effective values = case reverse values of
        value : _ | not (BS.null value) -> Just value
        _ -> Nothing
    single [value] | not (BS.null value) = Just value
    single _ = Nothing
    refIssue problem =
        let (code, raw, message) = case problem of
                Refs.RefTransportFailure value -> ("refs_unavailable", Nothing, show value)
                Refs.RefCommandFailure result -> ("refs_incomplete", Nothing, "Ref enumeration " ++ show (gitExitCode result) ++ ": " ++ show (gitStderr result))
                Refs.MalformedRefOutput row -> ("invalid_ref_observation", Just row, "Malformed ref observation: " ++ show row)
                Refs.InvalidRefObject row reason -> ("invalid_ref_object", Just row, reason ++ ": " ++ show row)
                Refs.DuplicateNodeRef row -> ("duplicate_node_ref", Just row, "Conflicting or repeated ref: " ++ show row)
            node = raw >>= Refs.localNode . BS.takeWhile (/= 0)
         in issue code node Nothing message
    deduplicate = Set.toAscList . Set.fromList
