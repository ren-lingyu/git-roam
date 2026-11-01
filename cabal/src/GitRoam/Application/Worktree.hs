{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Worktree (
    DeploymentPlan,
    RemovalPlan,
    ProtectedSession,
    planDeployment,
    planRemoval,
    deploymentRoot,
    pendingDeployments,
    existingDeployments,
    removalTargets,
    retainedMainWorktrees,
    withProtectedSession,
    addPlannedWorktree,
    removePlannedWorktree,
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

data DeploymentPlan = DeploymentPlan FilePath ManagedState (Map NodeId FilePath) [(NodeId, FilePath)]
    deriving (Eq, Show)
data RemovalPlan = RemovalPlan ManagedState [Worktree] [Worktree] [Worktree]
    deriving (Eq, Show)
data ProtectedSession = ProtectedSession (Git IO) FilePath (IORef (Set.Set BS.ByteString))

deploymentRoot :: DeploymentPlan -> FilePath
deploymentRoot (DeploymentPlan root _ _ _) = root
existingDeployments :: DeploymentPlan -> Map NodeId FilePath
existingDeployments (DeploymentPlan _ _ existing _) = existing
pendingDeployments :: DeploymentPlan -> [(NodeId, FilePath)]
pendingDeployments (DeploymentPlan _ _ _ pending) = pending
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
    unless (Map.fromList pairs == managedRefs state) (throwE "Managed refs changed or the supplied snapshot is not repository-wide")
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
planDeployment git directory state requestedRoot = guardIO $ runExceptT $ do
    (repository, records) <- ExceptT (observation git directory state)
    root <- ExceptT (safeAbsolutePath (if isAbsolute requestedRoot then requestedRoot else directory </> requestedRoot))
    common <- lift (decodePath (repositoryCommonDirectory repository))
    unless (not (within common root)) (throwE "Deployment root is inside Git administration data")
    selected <- forM (Map.keys (managedRefs state)) $ \node -> do
        let matches = filter ((== Just node) . worktreeNode) records
        case matches of
            [] -> pure (node, Nothing)
            [record] | not (treeMain record) -> do
                path <- ExceptT (registered git repository record)
                pure (node, Just path)
            _ -> throwE ("Node is checked out in main or duplicate worktrees: " ++ show node)
    paths <- lift (mapM (decodePath . treePath) records)
    when (root `elem` paths) (throwE "Deployment root equals a worktree root")
    let existing = Map.fromList [(node, path) | (node, Just path) <- selected]
        targets = [(node, root </> shortName node) | node <- Map.keys (managedRefs state)]
        pending = [(node, path) | (node, path) <- targets, Map.notMember node existing]
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
    pure (DeploymentPlan root state existing pending)

outerIgnore :: Git IO -> FilePath -> IO (Either String ())
outerIgnore git root = runExceptT $ do
    nearest <- lift (existingParent root)
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
planRemoval git directory state = guardIO $ runExceptT $ do
    (repository, records) <- ExceptT (observation git directory state)
    let managed record = maybe False (`Map.member` managedRefs state) (worktreeNode record)
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
addPlannedWorktree (ProtectedSession git directory _) plan@(DeploymentPlan root state _ _) node = guardIO $ runExceptT $ do
    target <- maybe (throwE "Node is not a pending deployment") pure (lookup node (pendingDeployments plan))
    refreshed <- ExceptT (planDeployment git directory state root)
    unless (lookup node (pendingDeployments refreshed) == Just target) (throwE "Deployment plan is stale")
    lift (createDirectoryIfMissing True root)
    _ <- ExceptT (planDeployment git directory state root)
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
