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

import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import GitRoam.Application.Protection (ProtectionState, observeProtection)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import qualified GitRoam.Git.Refs as Refs
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Repository

-- Later phases add commit metadata and working-tree status to this model.
data NodeProperty = TipProperty | WorktreesProperty | RemoteProperty deriving (Eq, Ord, Show)
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
        before <- Refs.readNodeRefs safeGit directory environment format scope
        trees <- if wants WorktreesProperty then Just <$> Worktrees.listWorktrees safeGit directory format else pure Nothing
        configs <- if wants RemoteProperty then Just <$> Refs.readUpstreamConfig safeGit directory environment else pure Nothing
        after <- Refs.readNodeRefs safeGit directory environment format scope
        let localRefs = Map.fromList [(Refs.observedNode ref, ref) | ref <- Refs.observationRefs before, Refs.observedRemotePrefix ref == Nothing]
            chosen = case selection of AllNodes -> Map.keys localRefs; SelectedNodes values -> Set.toAscList values
            registered = case trees of
                Just (Right records) -> Just (Map.map reverse (Map.fromListWith (++) [(node, [tree]) | tree <- records, Just node <- [Worktrees.worktreeNode tree]]))
                _ -> Nothing
            remoteCandidates = [ref | ref <- Refs.observationRefs before, Refs.observedRemotePrefix ref /= Nothing]
            tracking = Map.map reverse (Map.fromListWith (++) [(Refs.observedNode ref, [(Refs.observedRef ref, Refs.observedTip ref)]) | ref <- remoteCandidates, BS.null (Refs.observedSymbolic ref)])
            configMap = case configs of Just (Right values) -> Just values; _ -> Nothing
            build node =
                let found = Map.lookup node localRefs
                    (upstream, upstreamIssues) = upstreamFor node found configMap
                    row =
                        NodeStatus
                            node
                            (if not (wants TipProperty) then NotRequested else case found of Just ref | BS.null (Refs.observedSymbolic ref) -> Available (Refs.observedTip ref); _ -> Unavailable)
                            (if not (wants WorktreesProperty) then NotRequested else maybe Unavailable (Available . Map.findWithDefault [] node) registered)
                            (if not (wants RemoteProperty) then NotRequested else Available (RemoteObservation upstream (let refs = Map.findWithDefault [] node tracking in if Refs.observationComplete before || not (null refs) then Just refs else Nothing)))
                    missing = case found of
                        Nothing -> [issue (if Refs.observationComplete before then "node_not_found" else "node_unavailable") (Just node) Nothing "No reliable local Node ref was observed"]
                        Just ref | not (BS.null (Refs.observedSymbolic ref)) -> [issue "symbolic_node_branch" (Just node) (Just TipProperty) "The Node branch is symbolic"]
                        _ -> []
                 in (row, missing ++ [value | wants RemoteProperty, value <- upstreamIssues])
            rows = map build chosen
            fingerprint observed = Map.fromList [(Refs.observedRef ref, (Refs.observedTip ref, Refs.observedSymbolic ref, Refs.observedUpstream ref)) | ref <- Refs.observationRefs observed]
            changed = [issue "observation_changed" Nothing Nothing "Refs changed during the query; results are not a consistent snapshot" | fingerprint before /= fingerprint after]
            refIssues = map refIssue (Refs.observationErrors before ++ Refs.observationErrors after)
            treeIssues = case trees of Just (Left problem) -> [issue "worktrees_unavailable" Nothing (Just WorktreesProperty) problem]; _ -> []
            configIssues = case configs of Just (Left problem) -> [issue "upstream_unavailable" Nothing (Just RemoteProperty) problem]; _ -> []
            symbolicRemote = [issue "symbolic_remote_ref" (Just (Refs.observedNode ref)) (Just RemoteProperty) "A remote Node candidate is symbolic" | ref <- remoteCandidates, not (BS.null (Refs.observedSymbolic ref))]
        pure (NodesReport (map fst rows) (deduplicate (refIssues ++ treeIssues ++ configIssues ++ symbolicRemote ++ concatMap snd rows ++ changed)))
    upstreamFor node found configs = case configs of
        Nothing -> (Unavailable, [])
        Just values -> case Map.lookup node values of
            Nothing -> (Available Nothing, [])
            Just config ->
                let remote = single (Refs.upstreamRemotes config)
                    source = single (Refs.upstreamSources config)
                    unambiguous = remote /= Nothing && source /= Nothing
                    resolved = if unambiguous then found >>= Refs.observedUpstream else Nothing
                    issues =
                        [issue "upstream_ambiguous" (Just node) (Just RemoteProperty) "Upstream configuration is incomplete or does not identify a single upstream" | not unambiguous]
                            ++ [issue "upstream_unresolved" (Just node) (Just RemoteProperty) "Configured upstream cannot be resolved to a local ref" | unambiguous && resolved == Nothing]
                 in (Available (Just (UpstreamObservation remote source resolved)), issues)
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
