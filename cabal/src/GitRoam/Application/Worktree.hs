{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Worktree (
    DeploymentPlan,
    RemovalPlan,
    ProtectedSession,
    planDeployment,
    planDeploymentCandidate,
    planDeploymentCandidateFor,
    planRemoval,
    planRemovalFor,
    planDiscardRemoval,
    deploymentRoot,
    deploymentRefs,
    pendingDeployments,
    existingDeployments,
    removalTargets,
    retainedMainWorktrees,
    withProtectedSession,
    addPlannedWorktree,
    removePlannedWorktree,
    restoreRemovedWorktree,
    checkRemovedWorktreePaths,
) where

import Control.Exception (IOException, throwIO, try)
import Control.Monad (forM, forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Char (isLower)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Set as Set
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor, withOperationLock)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath
import System.IO.Error (isDoesNotExistError)
import qualified System.Posix.Files as Files

data DeploymentPlan = DeploymentPlan FilePath ManagedState (Map NodeId FilePath) [(NodeId, FilePath)] (Set.Set NodeId)
    deriving (Eq, Show)
data RemovalPlan = RemovalPlan ManagedState [Worktree] [Worktree] [Worktree]
    deriving (Eq, Show)
data ProtectedSession = ProtectedSession (Git IO) FilePath (IORef (Set.Set BS.ByteString))

deploymentRoot :: DeploymentPlan -> FilePath
deploymentRoot (DeploymentPlan root _ _ _ _) = root
deploymentRefs :: DeploymentPlan -> Map NodeId ObjectId
deploymentRefs (DeploymentPlan _ state _ _ _) = managedRefs state
existingDeployments :: DeploymentPlan -> Map NodeId FilePath
existingDeployments (DeploymentPlan _ _ existing _ _) = existing
pendingDeployments :: DeploymentPlan -> [(NodeId, FilePath)]
pendingDeployments (DeploymentPlan _ _ _ pending _) = pending
removalTargets :: RemovalPlan -> [Worktree]
removalTargets (RemovalPlan _ targets _ _) = targets
retainedMainWorktrees :: RemovalPlan -> [Worktree]
retainedMainWorktrees (RemovalPlan _ _ mains _) = mains

guardIO :: IO (Either String a) -> IO (Either String a)
guardIO action = do
    result <- try action
    pure $ case result of
        Left problem -> Left (show (problem :: IOException))
        Right value -> value

request :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String GitResult)
request git directory arguments input = do
    result <- runGit git (GitInvocation directory arguments input pathEnvironment)
    pure (either (Left . show) Right result)

pathEnvironment :: [(String, Maybe String)]
pathEnvironment = readOnlyEnvironment ++ [(key, Nothing) | key <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

command :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
command git directory arguments input = do
    outcome <- request git directory arguments input
    pure $
        outcome >>= \result ->
            if gitExitCode result == ExitSuccess && (take 1 arguments /= ["for-each-ref"] || BS.null (gitStderr result))
                then Right (gitStdout result)
                else Left (show arguments ++ ": " ++ show (gitStderr result))

exists :: FilePath -> IO Bool
exists path = do
    result <- try (Files.getSymbolicLinkStatus path)
    case result of
        Right _ -> pure True
        Left problem
            | isDoesNotExistError problem -> pure False
            | otherwise -> throwIO (problem :: IOException)

observation :: Git IO -> FilePath -> ManagedState -> IO (Either String (Repository, [Worktree]))
observation git directory state = runExceptT $ do
    ExceptT (observeRefs git directory (managedRefs state))

observeRefs :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either String (Repository, [Worktree]))
observeRefs git directory expected = runExceptT $ do
    found <- lift (inspectRepository git directory pathEnvironment)
    repository <- either (throwE . show) pure found
    bytes <- ExceptT (command git directory ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"] BS.empty)
    pairs <- fmap concat $ forM (BSC.lines bytes) $ \row -> case BS.split 0 row of
        [ref, oid, sym] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> pure []
            Just node -> do
                unless (BS.null sym) (throwE "Symbolic Node ref in worktree plan")
                object <- either throwE pure (parseObjectId (repositoryObjectFormat repository) oid)
                pure [(node, object)]
        _ -> throwE "Malformed ref observation"
    unless (Map.fromList pairs == expected) (throwE "Managed refs changed or the supplied snapshot is not repository-wide")
    records <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    pure (repository, records)

registered :: Git IO -> Repository -> Worktree -> IO (Either String FilePath)
registered git repository record = runExceptT $ do
    unless (treeLocked record == Nothing && treePrunable record == Nothing) (throwE "Locked or prunable worktree")
    path <- lift (decodePath (treePath record))
    checkedPath <- ExceptT (safeAbsolutePath path)
    present <- lift (doesDirectoryExist checkedPath)
    unless present (throwE ("Missing worktree: " ++ show path))
    actual <- lift (inspectRepository git checkedPath pathEnvironment)
    discovered <- either (throwE . show) pure actual
    unless
        ( repositoryCommonDirectory discovered == repositoryCommonDirectory repository
            && repositoryWorktree discovered == Just (treePath record)
        )
        (throwE "Worktree registration does not match its directory")
    branch <- ExceptT (command git checkedPath ["symbolic-ref", "-q", "HEAD"] BS.empty)
    unless (Just (BS.take (BS.length branch - 1) branch) == treeBranch record) (throwE "Worktree branch changed")
    pure checkedPath

planDeployment :: Git IO -> FilePath -> ManagedState -> FilePath -> IO (Either String DeploymentPlan)
planDeployment git directory state = planDeploymentCandidate git directory (managedRefs state) state

-- Preflight the complete target before creating missing local branches. Current
-- refs may lack dependency branches; only the supplied final state is validated.
planDeploymentCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> ManagedState -> FilePath -> IO (Either String DeploymentPlan)
planDeploymentCandidate git directory current state = planDeploymentCandidateFor git directory current state (Map.keysSet (managedRefs state))

-- Internal operation scope: node creation targets only its new Node. Normal
-- public deploy still targets the complete managed set. Unrelated main/locked
-- deployments are not operations on the new Node, but root reuse must still
-- recognize only valid actual linked worktree directories.
planDeploymentCandidateFor :: Git IO -> FilePath -> Map NodeId ObjectId -> ManagedState -> Set.Set NodeId -> FilePath -> IO (Either String DeploymentPlan)
planDeploymentCandidateFor git directory current state wanted requestedRoot = guardIO $ runExceptT $ do
    unless (wanted `Set.isSubsetOf` Map.keysSet (managedRefs state)) (throwE "Unknown Node in internal deployment scope")
    (repository, records) <- ExceptT (observeRefs git directory current)
    root <- ExceptT (safeAbsolutePath (if isAbsolute requestedRoot then requestedRoot else directory </> requestedRoot))
    common <- lift (decodePath (repositoryCommonDirectory repository))
    unless (not (within common root)) (throwE "Deployment root is inside Git administration data")
    selected <- forM (Map.keys (managedRefs state)) $ \node -> do
        let matches = filter ((== Just node) . worktreeNode) records
        case matches of
            [] -> pure (node, Nothing)
            [record] | Set.notMember node wanted && not (treeMain record) -> do
                preserved <- lift (registered git repository record{treeLocked = Nothing})
                pure (node, either (const Nothing) Just preserved)
            _ | Set.notMember node wanted -> pure (node, Nothing)
            [record] | not (treeMain record) -> do
                path <- ExceptT (registered git repository record)
                pure (node, Just path)
            _ -> throwE ("Node is checked out in main or duplicate worktrees: " ++ show node)
    paths <- lift (mapM (decodePath . treePath) records)
    when (root `elem` paths) (throwE "Deployment root equals a worktree root")
    let existing = Map.fromList [(node, path) | (node, Just path) <- selected]
        targets = [(node, root </> shortName node) | node <- Map.keys (managedRefs state)]
        pending = [(node, path) | (node, path) <- targets, Set.member node wanted, Map.notMember node existing]
    either throwE pure (checkPathCollisions targets)
    isPresent <- lift (exists root)
    when isPresent $ do
        isDirectory <- lift (doesDirectoryExist root)
        unless isDirectory (throwE "Deployment root is not a directory")
        children <- lift (listDirectory root)
        unless (all (\child -> root </> child `elem` Map.elems existing) children) (throwE "Deployment root contains unrelated data or worktrees")
    forM_ pending $ \(_, path) -> do
        occupied <- lift (exists path)
        when occupied (throwE ("Occupied deployment target: " ++ show path))
    ExceptT (outerIgnore git root)
    pure (DeploymentPlan root state existing pending wanted)

outerIgnore :: Git IO -> FilePath -> IO (Either String ())
outerIgnore git root = outerIgnoreFrom git root root

outerIgnoreFrom :: Git IO -> FilePath -> FilePath -> IO (Either String ())
outerIgnoreFrom git root search = runExceptT $ do
    nearest <- lift (existingParent search)
    result <- ExceptT (request git nearest ["rev-parse", "--is-inside-work-tree"] BS.empty)
    case (gitExitCode result, gitStdout result) of
        (ExitSuccess, "true\n") -> do
            top <- ExceptT (command git nearest ["rev-parse", "--path-format=absolute", "--show-toplevel"] BS.empty)
            topPath <- lift (decodePath (BS.init top))
            when (root == topPath) (throwE "Deployment root equals an outer worktree root")
            tracked <- ExceptT (command git nearest ["ls-files", "-z", "--", root] BS.empty)
            unless (BS.null tracked) (throwE "Deployment root contains tracked outer-repository paths")
            ignored <- ExceptT (request git nearest ["check-ignore", "--quiet", "--no-index", "--", addTrailingPathSeparator root] BS.empty)
            unless (gitExitCode ignored == ExitSuccess) (throwE "Nested deployment root is not wholly ignored by the outer repository")
        (ExitSuccess, _) -> throwE "Deployment root is inside Git administration data"
        (ExitFailure 128, _) -> do
            metadata <- lift (hasMetadata nearest)
            when metadata (throwE "Cannot establish the outer repository's ignore protection")
        _ -> throwE ("Cannot inspect outer repository: " ++ show (gitStderr result))
  where
    existingParent path = do
        present <- doesDirectoryExist path
        if present then pure path else existingParent (takeDirectory path)
    hasMetadata path = do
        dotGit <- exists (path </> ".git")
        bareHead <- exists (path </> "HEAD")
        bareObjects <- doesDirectoryExist (path </> "objects")
        if dotGit || (bareHead && bareObjects)
            then pure True
            else if takeDirectory path == path then pure False else hasMetadata (takeDirectory path)

planRemoval :: Git IO -> FilePath -> ManagedState -> IO (Either String RemovalPlan)
planRemoval git directory state = planRemovalFor git directory state (Map.keysSet (managedRefs state))

-- Internal selection for compensation/history coordination only. This is not a
-- public partial-undeploy interface.
planRemovalFor :: Git IO -> FilePath -> ManagedState -> Set.Set NodeId -> IO (Either String RemovalPlan)
planRemovalFor git directory state selected = guardIO $ runExceptT $ do
    (repository, records) <- ExceptT (observation git directory state)
    let managed record = maybe False (`Set.member` selected) (worktreeNode record)
        targets = sortOn (Down . BS.length . treePath) [r | r <- records, managed r, not (treeMain r)]
        mains = [r | r <- records, managed r, treeMain r]
        nodes = [node | record <- records, managed record, Just node <- [worktreeNode record]]
    unless (length nodes == Set.size (Set.fromList nodes)) (throwE "Node branch has duplicate worktree checkouts")
    common <- lift (decodePath (repositoryCommonDirectory repository))
    forM_ targets $ \record -> do
        path <- ExceptT (registered git repository record)
        when (within path common) (throwE "Removal would delete shared Git administration data")
        headOid <- maybe (throwE "Node worktree has no committed HEAD") pure (treeHead record)
        unless (Map.lookup (maybe (error "Managed record has no Node") id (worktreeNode record)) (managedRefs state) == Just headOid) (throwE "Worktree HEAD differs from its branch")
        let children = [r | r <- records, treePath r /= treePath record, (treePath record <> "/") `BS.isPrefixOf` treePath r]
        unless (all (`elem` targets) children) (throwE "Removal would touch a non-target nested worktree")
        nested <- lift (mapM (decodePath . treePath) children)
        ExceptT (removable git path nested)
    pure (RemovalPlan state targets mains records)

-- Recreating worktrees cannot preserve arbitrary private administration state.
-- Refuse those layouts before history changes rather than silently losing it.
planDiscardRemoval :: Git IO -> FilePath -> ManagedState -> Set.Set NodeId -> IO (Either String RemovalPlan)
planDiscardRemoval git directory state selected = guardIO $ runExceptT $ do
    plan@(RemovalPlan _ targets mains records) <- ExceptT (planRemovalFor git directory state selected)
    unless (null mains) (throwE "Affected Node is checked out in the main worktree; undeploy or safely change that checkout first")
    forM_ targets $ \record -> do
        when (any (\other -> treePath other /= treePath record && (treePath record <> "/") `BS.isPrefixOf` treePath other) records) $
            throwE "Affected worktree contains a nested worktree; undeploy before discarding this history"
        path <- lift (decodePath (treePath record))
        ExceptT (outerIgnoreFrom git path (takeDirectory path))
        config <- ExceptT (command git path ["rev-parse", "--path-format=absolute", "--git-path", "config.worktree"] BS.empty)
        configPath <- lift (decodePath (BS.init config))
        configured <- lift (exists configPath)
        when configured (throwE "Affected worktree has private configuration that recreation cannot preserve")
        refs <- ExceptT (command git path ["for-each-ref", "--format=%(refname)", "refs/worktree/", "refs/bisect/", "refs/rewritten/"] BS.empty)
        unless (BS.null refs) (throwE "Affected worktree has private refs that recreation cannot preserve")
    pure plan

removable :: Git IO -> FilePath -> [FilePath] -> IO (Either String ())
removable git path nested = runExceptT $ do
    -- In-progress sequencers may have an otherwise completely clean index/tree.
    forM_ ["MERGE_HEAD", "rebase-merge", "rebase-apply", "REBASE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_START", "sequencer", "index.lock"] $ \name -> do
        location <- ExceptT (command git path ["rev-parse", "--path-format=absolute", "--git-path", name] BS.empty)
        nativePath <- lift (decodePath (BS.init location))
        active <- lift (exists nativePath)
        when active (throwE ("In-progress Git operation: " ++ name))
    index <- ExceptT (command git path ["ls-files", "--stage", "-z"] BS.empty)
    flags <- ExceptT (command git path ["ls-files", "-v", "-z"] BS.empty)
    when
        (any (\entry -> not (BS.null entry) && (BSC.head entry == 'S' || isLower (BSC.head entry))) (BS.split 0 flags))
        (throwE "Assume-unchanged or skip-worktree index entries cannot be removed safely")
    files <- forM (filter (not . BS.null) (BS.split 0 index)) $ \entry -> case BSC.break (== '\t') entry of
        (header, suffix)
            | not (BS.null suffix)
            , [mode, _, stage] <- BSC.words header -> do
                unless (stage == "0" && mode /= "160000") (throwE "Unmerged index or submodule checkout cannot be removed safely")
                file <- lift (decodePath (BS.drop 1 suffix))
                unless (not (isAbsolute file) && all (/= "..") (splitDirectories file)) (throwE "Invalid index pathname")
                pure (path </> file)
        _ -> throwE "Malformed index entry"
    when (any (\child -> any (within child) files) nested) (throwE "Nested worktree overlaps tracked outer paths")
    let ancestors file = takeWhile (\p -> p /= path && within path p) (iterate takeDirectory (takeDirectory file))
        allowedDirectories = Set.fromList (concatMap ancestors (files ++ nested))
        allowedFiles = Set.fromList files
        related file = any (\child -> within child file || within file child) nested
    status <- ExceptT (command git path ["-c", "core.fsmonitor=false", "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=matching"] BS.empty)
    forM_ (filter (not . BS.null) (BS.split 0 status)) $ \entry -> do
        file <- lift (decodePath (BS.drop 3 entry))
        unless
            (("?? " `BS.isPrefixOf` entry || "!! " `BS.isPrefixOf` entry) && related (dropTrailingPathSeparator (path </> file)))
            (throwE ("Dirty or ignored worktree data: " ++ show path))
    admin <- lift (Files.getSymbolicLinkStatus (path </> ".git"))
    unless (Files.isRegularFile admin) (throwE "Linked worktree .git is not an ordinary administrative file")
    let scan current = do
            names <- lift (listDirectory current)
            forM_ names $ \name -> do
                let file = current </> name
                unless (file == path </> ".git" || file `elem` nested) $ do
                    info <- lift (Files.getSymbolicLinkStatus file)
                    if Files.isDirectory info
                        then do
                            unless (Set.member file allowedDirectories) (throwE ("Untracked directory would be lost: " ++ show file))
                            scan file
                        else
                            unless
                                (Set.member file allowedFiles && (Files.isRegularFile info || Files.isSymbolicLink info))
                                (throwE ("Untracked or special file would be lost: " ++ show file))
    scan path

withProtectedSession :: FilePath -> Git IO -> FilePath -> (ProtectedSession -> IO (Either String a)) -> IO (Either String a)
withProtectedSession executable git directory action = withOperationLock directory $ do
    healthy <- requireProtectionFor executable directory
    case healthy of
        Left problem -> pure (Left problem)
        Right () -> do
            found <- inspectRepository git directory pathEnvironment
            case found of
                Left problem -> pure (Left (show problem))
                Right repository -> do
                    common <- decodePath (repositoryCommonDirectory repository)
                    newIORef Set.empty >>= action . ProtectedSession git common

addPlannedWorktree :: ProtectedSession -> DeploymentPlan -> NodeId -> IO (Either String ())
addPlannedWorktree (ProtectedSession git directory _) plan@(DeploymentPlan root state _ _ wanted) node = guardIO $ runExceptT $ do
    target <- maybe (throwE "Node is not a pending deployment") pure (lookup node (pendingDeployments plan))
    refreshed <- ExceptT (planDeploymentCandidateFor git directory (managedRefs state) state wanted root)
    unless (lookup node (pendingDeployments refreshed) == Just target) (throwE "Deployment plan is stale")
    lift (createDirectoryIfMissing True root)
    _ <- ExceptT (planDeploymentCandidateFor git directory (managedRefs state) state wanted root)
    _ <- ExceptT (command git directory (ownHookBypass ++ ["worktree", "add", "--no-guess-remote", "--", target, BSC.unpack (nodeIdBytes node)]) BS.empty)
    (_, records) <- ExceptT (observation git directory state)
    pathBytes <- lift (encodePath target)
    unless (length [r | r <- records, treePath r == pathBytes, worktreeNode r == Just node] == 1) (throwE "Git did not establish the planned worktree; inspect residual state")

removePlannedWorktree :: ProtectedSession -> RemovalPlan -> NodeId -> IO (Either String ())
removePlannedWorktree (ProtectedSession git directory removedRef) (RemovalPlan state targets _ original) node = guardIO $ runExceptT $ do
    record <- case filter ((== Just node) . worktreeNode) targets of
        [value] -> pure value
        _ -> throwE "Node is not a unique removal target"
    removed <- lift (readIORef removedRef)
    (repository, records) <- ExceptT (observation git directory state)
    unless (filter (\r -> Set.notMember (treePath r) removed) original == records) (throwE "Worktree observation changed since planning")
    path <- ExceptT (registered git repository record)
    let nestedRecords = [r | r <- targets, (treePath record <> "/") `BS.isPrefixOf` treePath r]
    unless (all (\r -> Set.member (treePath r) removed) nestedRecords) (throwE "Remove nested Node worktrees first")
    nested <- lift (mapM (decodePath . treePath) nestedRecords)
    ExceptT (removable git path nested)
    _ <- ExceptT (command git directory (ownHookBypass ++ ["worktree", "remove", "--", path]) BS.empty)
    present <- lift (exists path)
    remaining <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    when (present || any ((== treePath record) . treePath) remaining) (throwE "Worktree removal left residual state")
    lift (modifyIORef' removedRef (Set.insert (treePath record)))

-- Only the session that confirmed removal can restore a path. An occupied path,
-- competing checkout or changed ref set is never overwritten or force-cleaned.
restoreRemovedWorktree :: ProtectedSession -> ManagedState -> Worktree -> IO (Either String ())
restoreRemovedWorktree (ProtectedSession git directory removedRef) state original = guardIO $ runExceptT $ do
    removed <- lift (readIORef removedRef)
    unless (Set.member (treePath original) removed) (throwE "Worktree removal was not confirmed by this operation")
    node <- maybe (throwE "Restoration target is not a Node worktree") pure (worktreeNode original)
    oid <- maybe (throwE "Restoration Node branch is absent") pure (Map.lookup node (managedRefs state))
    (_, records) <- ExceptT (observation git directory state)
    when (any (\r -> treePath r == treePath original || worktreeNode r == Just node) records) (throwE "Restoration path or Node checkout is already registered")
    path <- ExceptT (restorationPath git original)
    _ <- ExceptT (command git directory (ownHookBypass ++ ["worktree", "add", "--no-guess-remote", "--", path, BSC.unpack (nodeIdBytes node)]) BS.empty)
    (repository, after) <- ExceptT (observation git directory state)
    restored <- case [r | r <- after, treePath r == treePath original, worktreeNode r == Just node, treeHead r == Just oid] of
        [r] -> pure r
        _ -> throwE "Restored worktree could not be verified; inspect residual state"
    _ <- ExceptT (registered git repository restored)
    ExceptT (removable git path [])
    lift (modifyIORef' removedRef (Set.delete (treePath original)))

checkRemovedWorktreePaths :: ProtectedSession -> [Worktree] -> IO (Either String ())
checkRemovedWorktreePaths (ProtectedSession git _ removedRef) records = guardIO $ runExceptT $ do
    removed <- lift (readIORef removedRef)
    forM_ records $ \record -> do
        unless (Set.member (treePath record) removed) (throwE "Worktree removal was not confirmed")
        _ <- ExceptT (restorationPath git record)
        pure ()

restorationPath :: Git IO -> Worktree -> IO (Either String FilePath)
restorationPath git record = runExceptT $ do
    path <- lift (decodePath (treePath record)) >>= ExceptT . safeAbsolutePath
    occupied <- lift (exists path)
    when occupied (throwE "Restoration path is occupied; user data is retained")
    parent <- lift (doesDirectoryExist (takeDirectory path))
    unless parent (throwE "Restoration parent directory disappeared")
    ExceptT (outerIgnore git path)
    pure path
