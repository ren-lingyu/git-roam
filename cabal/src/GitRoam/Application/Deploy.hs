{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Deploy (deploy, DeploymentResult (..), DeploymentFailure (..)) where

import Control.Exception (IOException, try)
import Control.Monad (forM, forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Inspect (validateCandidate)
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Worktree
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath, encodePath)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, (</>))

data DeploymentResult = DeploymentResult
    { deployedWorktrees :: [(NodeId, FilePath)]
    , trackingSources :: [(NodeId, BS.ByteString)]
    }
    deriving (Eq, Show)
data DeploymentFailure = DeploymentFailure String [String] deriving (Eq, Show)
data Source = Source BS.ByteString BS.ByteString ObjectId deriving (Eq, Ord, Show)
data Snapshot = Snapshot (Map.Map NodeId ObjectId) [(BS.ByteString, ObjectId)] deriving (Eq, Show)

environment :: [(String, Maybe String)]
environment = readOnlyEnvironment ++ [(name, Nothing) | name <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    outcome <- runGit git (GitInvocation directory args input environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess && ("for-each-ref" `notElem` args || BS.null (gitStderr result)) -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

readSnapshot :: Git IO -> FilePath -> ObjectFormat -> IO (Either String Snapshot)
readSnapshot git directory format = runExceptT $ do
    bytes <- ExceptT (query git directory ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/", "refs/remotes/"] "")
    rows <- fmap concat $ forM (BSC.lines bytes) $ \row -> case BS.split 0 row of
        [name, oid, symbolic] -> case localNode name of
            Just node -> do
                unless (BS.null symbolic) (throwE "Symbolic local Node branch")
                object <- either throwE pure (parseObjectId format oid)
                pure [(Left node, object)]
            Nothing -> case remoteNode name of
                Just _ -> do
                    unless (BS.null symbolic) (throwE "Symbolic remote Node candidate")
                    object <- either throwE pure (parseObjectId format oid)
                    pure [(Right name, object)]
                Nothing -> pure []
        _ -> throwE "Malformed Node ref observation"
    pure (Snapshot (Map.fromList [(node, oid) | (Left node, oid) <- rows]) [(name, oid) | (Right name, oid) <- rows])
  where
    localNode name = BS.stripPrefix "refs/heads/" name >>= either (const Nothing) Just . parseNodeId

remoteNode :: BS.ByteString -> Maybe (BS.ByteString, NodeId)
remoteNode ref = do
    suffix <- BS.stripPrefix "refs/remotes/" ref
    let (prefix, uuid) = BSC.breakEnd (== '/') suffix
    if BS.null prefix
        then Nothing
        else do
            node <- either (const Nothing) Just (parseNodeId uuid)
            pure (BS.init prefix, node)

selectSources :: Maybe BS.ByteString -> Snapshot -> Either String (Map.Map NodeId Source)
selectSources chosen (Snapshot locals remotes) = traverse select grouped
  where
    grouped =
        Map.fromListWith
            (++)
            [ (node, [Source remote ref oid])
            | (ref, oid) <- remotes
            , Just (remote, node) <- [remoteNode ref]
            , Map.notMember node locals
            , maybe True (== remote) chosen
            ]
    select sources = case sortOn id sources of
        [] -> Left "Missing source"
        first@(Source _ _ oid) : rest | all (\(Source _ _ other) -> other == oid) rest -> Right first
        alternatives -> Left ("Ambiguous remote Node history; specify --remote: " ++ show alternatives)

-- Git handles reference locking, tracking configuration and worktree checkout.
-- The validated complete target precedes all structural writes.
deploy :: FilePath -> Git IO -> FilePath -> FilePath -> Maybe String -> IO (Either DeploymentFailure DeploymentResult)
deploy executable git directory path remote = do
    established <- newIORef False
    attempted <- newIORef Set.empty
    let observedGit =
            observeGit
                ( \invocation -> do
                    let args = gitArguments invocation
                    case reverse args of
                        name : _
                            | "worktree" `elem` args && "add" `elem` args
                            , Right node <- parseNodeId (BSC.pack name) ->
                                modifyIORef' attempted (Set.insert node)
                        _ -> pure ()
                )
                git
    outcome <- try $ withProtectedSession executable observedGit directory $ \session -> do
        prepared <- prepare
        case prepared of
            Left problem -> pure (Left problem)
            Right (common, format, before, state, sources, plan) -> do
                applied <- apply established session common format before state sources plan
                case applied of
                    Right result -> pure (Right (Right result))
                    Left problem -> do
                        installed <- readIORef established
                        started <- readIORef attempted
                        details <- compensate git session common format (if installed then sources else Map.empty) started plan
                        pure (Right (Left (DeploymentFailure problem details)))
    pure $ case outcome of
        Left problem -> Left (DeploymentFailure (show (problem :: IOException)) ["Operation interrupted; inspect actual refs and worktrees before continuing."])
        Right (Left problem) -> Left (DeploymentFailure problem [])
        Right (Right value) -> value
  where
    prepare = runExceptT $ do
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        let format = repositoryObjectFormat repository
        shallow <- ExceptT (query git common ["rev-parse", "--is-shallow-repository"] "")
        unless (shallow == "false\n") (throwE "Complete deployment requires non-shallow history")
        before@(Snapshot locals _) <- ExceptT (readSnapshot git common format)
        remoteBytes <- lift (mapM encodePath remote)
        case remoteBytes of
            Nothing -> pure ()
            Just name -> do
                known <- ExceptT (query git common ["remote"] "")
                unless (name `elem` BSC.lines known) (throwE "Unknown remote selected for deployment")
        sources <- either throwE pure (selectSources remoteBytes before)
        let target = Map.union locals (Map.map (\(Source _ _ oid) -> oid) sources)
        state <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common target))
        plan <- ExceptT (planDeploymentCandidate git common locals state (if isAbsolute path then path else directory </> path))
        forM_ (Map.keys sources) $ \node -> do
            values <- configSection git common node
            unless (BS.null values) (throwE ("Existing branch configuration for missing Node: " ++ show node))
        after <- ExceptT (readSnapshot git common format)
        unless (before == after) (throwE "Node refs changed during deployment planning")
        pure (common, format, before, state, sources, plan)

    apply established session common format before@(Snapshot locals _) state sources plan = runExceptT $ do
        now <- ExceptT (readSnapshot git common format)
        unless (now == before) (throwE "Node refs changed before deployment execution")
        unless (Map.null sources) $ do
            let writes = [("create", node, oid) | (node, Source _ _ oid) <- Map.toList sources]
                checks = [(ref, oid) | Source _ ref oid <- Map.elems sources]
            _ <- ExceptT (transaction git common locals writes checks)
            lift (writeIORef established True)
            forM_ (Map.toList sources) $ \(node, Source _ ref _) -> do
                start <- lift (decodePath ref)
                _ <- ExceptT (query git common (ownHookBypass ++ ["branch", "--set-upstream-to=" ++ start, "--", BSC.unpack (nodeIdBytes node)]) "")
                pure ()
        forM_ (pendingDeployments plan) $ \(node, _) -> ExceptT (addPlannedWorktree session plan node)
        actual <- ExceptT (readSnapshot git common format)
        let Snapshot actualRefs _ = actual
        unless (actualRefs == managedRefs state) (throwE "Managed refs changed during deployment")
        _ <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common actualRefs))
        final <- ExceptT (planDeployment git common state (deploymentRoot plan))
        unless (null (pendingDeployments final)) (throwE "Deployment remains incomplete")
        pure (DeploymentResult (Map.toList (existingDeployments final)) [(node, ref) | (node, Source _ ref _) <- Map.toList sources])

configSection :: Git IO -> FilePath -> NodeId -> ExceptT String IO BS.ByteString
configSection git directory node = do
    result <- lift (runGit git (GitInvocation directory ["config", "--local", "--get-regexp", "^branch\\." ++ BSC.unpack (nodeIdBytes node) ++ "\\."] "" environment))
    case result of
        Right value | gitExitCode value == ExitSuccess -> pure (gitStdout value)
        Right value | gitExitCode value == ExitFailure 1 -> pure ""
        other -> throwE ("Cannot inspect branch configuration: " ++ show other)

transaction :: Git IO -> FilePath -> Map.Map NodeId ObjectId -> [(BS.ByteString, NodeId, ObjectId)] -> [(BS.ByteString, ObjectId)] -> IO (Either String BS.ByteString)
transaction git directory stable writes sources = query git directory (ownHookBypass ++ ["update-ref", "--stdin"]) payload
  where
    oid = objectIdBytes
    ref node = "refs/heads/" <> nodeIdBytes node
    payload =
        BSC.unlines
            ( ["start"]
                ++ ["verify " <> ref node <> " " <> oid old | (node, old) <- Map.toList stable, node `notElem` [n | (_, n, _) <- writes]]
                ++ [action <> " " <> ref node <> " " <> oid value | (action, node, value) <- writes]
                ++ ["verify " <> name <> " " <> oid value | (name, value) <- sources]
                ++ ["prepare", "commit"]
            )

-- Compensation never rewrites history. A changed/checked-out new branch stays;
-- dependencies required by retained histories stay with it. Unknown observations
-- cause conservative refusal rather than guessed rollback.
compensate :: Git IO -> ProtectedSession -> FilePath -> ObjectFormat -> Map.Map NodeId Source -> Set.Set NodeId -> DeploymentPlan -> IO [String]
compensate git session directory format sources attempted plan = do
    outcome <- runExceptT $ do
        Snapshot refs _ <- ExceptT (readSnapshot git directory format)
        state <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git directory refs))
        records <- ExceptT (listWorktrees git directory format)
        expectedPaths <- lift (mapM (\(node, p) -> do bytes <- encodePath p; pure (node, bytes)) (pendingDeployments plan))
        let unchanged node = Map.lookup node refs == Map.lookup node (managedRefsFromPlan sources)
            newlyChecked =
                Set.fromList
                    [ node
                    | (node, p) <- expectedPaths
                    , unchanged node
                    , Set.member node attempted
                    , r <- records
                    , treePath r == p
                    , worktreeNode r == Just node
                    , not (treeMain r)
                    ]
        removal <- lift (planRemovalFor git directory state newlyChecked)
        cleanup <- case removal of
            Left problem -> pure ["New worktrees retained: " ++ problem]
            Right removalPlan -> do
                outcomes <-
                    lift
                        ( mapM
                            ( \record -> case worktreeNode record of
                                Just node -> removePlannedWorktree session removalPlan node
                                Nothing -> pure (Left "Non-Node compensation target")
                            )
                            (removalTargets removalPlan)
                        )
                pure ["Worktree compensation refused/failed: " ++ problem | Left problem <- outcomes]
        Snapshot current _ <- ExceptT (readSnapshot git directory format)
        currentState <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git directory current))
        remaining <- ExceptT (listWorktrees git directory format)
        configurations <- forM (Map.toList sources) $ \(node, Source remote _ _) -> do
            section <- configSection git directory node
            pure (node, trackingUnchanged node remote section)
        let eligible =
                Set.fromList
                    [ node
                    | (node, Source _ _ oid) <- Map.toList sources
                    , Map.lookup node current == Just oid
                    , all ((/= Just node) . worktreeNode) remaining
                    , lookup node configurations == Just True
                    ]
            keepClosed candidates = case validateManagedState (managedHistory currentState) (Map.withoutKeys current candidates) of
                Right _ -> candidates
                Left problems ->
                    let required = Set.fromList [node | MissingDependencyBranch _ node _ <- problems]
                        smaller = candidates `Set.difference` required
                     in if Set.null required || smaller == candidates then Set.empty else keepClosed smaller
            deletions = keepClosed eligible
        unless (Set.null deletions) $ do
            _ <- ExceptT (transaction git directory current [("delete", node, oid) | node <- Set.toList deletions, Just oid <- [Map.lookup node current]] [])
            -- Remove only the exact tracking settings written by this invocation.
            forM_ (Set.toList deletions) $ \node -> case Map.lookup node sources of
                Nothing -> pure ()
                Just (Source remote _ _) -> do
                    section <- configSection git directory node
                    let prefix = "branch." <> nodeIdBytes node <> "."
                    unless (trackingUnchanged node remote section) (throwE "Changed branch configuration retained after ref compensation")
                    forM_ ["remote", "merge"] $ \key -> do
                        result <- lift (runGit git (GitInvocation directory ["config", "--local", "--unset-all", BSC.unpack (prefix <> key)] "" environment))
                        case result of
                            Right value | gitExitCode value `elem` [ExitSuccess, ExitFailure 5] -> pure ()
                            other -> throwE ("Tracking cleanup failed: " ++ show other)
        Snapshot final _ <- ExceptT (readSnapshot git directory format)
        _ <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git directory final))
        finalRecords <- ExceptT (listWorktrees git directory format)
        pure (cleanup ++ ["Remaining managed refs: " ++ show (Map.toList final), "Remaining Node worktrees: " ++ show [(worktreeNode r, treePath r) | r <- finalRecords, worktreeNode r /= Nothing]])
    pure $ either (\problem -> ["Compensation stopped; inspect residual refs/worktrees: " ++ problem]) id outcome
  where
    managedRefsFromPlan selected =
        Map.union
            (Map.fromList [(node, oid) | (node, Source _ _ oid) <- Map.toList selected])
            -- Existing branches may also receive new worktrees. Their planned OIDs
            -- are captured by the validated DeploymentPlan, not inferred from HEAD.
            (deploymentRefs plan)

trackingUnchanged :: NodeId -> BS.ByteString -> BS.ByteString -> Bool
trackingUnchanged node remote section = all (`Set.member` allowed) (BSC.lines section)
  where
    prefix = "branch." <> nodeIdBytes node <> "."
    allowed = Set.fromList [prefix <> "remote " <> remote, prefix <> "merge refs/heads/" <> nodeIdBytes node]
