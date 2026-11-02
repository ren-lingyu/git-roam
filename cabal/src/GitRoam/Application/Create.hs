{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Create (createNode, createNodeWith, CreationResult (..), CreationFailure (..)) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GitRoam.Application.Inspect (inspectState, reportManagedState, validateCandidate)
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Worktree
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths
import System.Directory (doesPathExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

data CreationResult = CreationResult
    { createdNode :: NodeId
    , createdRoot :: ObjectId
    , createdPath :: FilePath
    }
    deriving (Eq, Show)
data CreationFailure = CreationFailure String [String] deriving (Eq, Show)

environment :: [(String, Maybe String)]
environment = readOnlyEnvironment ++ [(name, Nothing) | name <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    outcome <- runGit git (GitInvocation directory args input environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess && ("for-each-ref" `notElem` args || BS.null (gitStderr result)) -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

stateAt :: Git IO -> FilePath -> IO (Either String ManagedState)
stateAt git directory = do
    outcome <- inspectState git directory [] Nothing
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right report -> either (Left . show) Right (reportManagedState report)

branchConfig :: Git IO -> FilePath -> NodeId -> IO (Either String BS.ByteString)
branchConfig git directory node = do
    outcome <- runGit git (GitInvocation directory ["config", "--local", "--get-regexp", "^branch\\." ++ BSC.unpack (nodeIdBytes node) ++ "\\."] "" environment)
    pure $ case outcome of
        Right result | gitExitCode result == ExitSuccess -> Right (gitStdout result)
        Right result | gitExitCode result == ExitFailure 1 -> Right ""
        other -> Left ("Cannot inspect branch configuration: " ++ show other)

createNode :: FilePath -> Git IO -> FilePath -> FilePath -> IO (Either CreationFailure CreationResult)
createNode = createNodeWith (UUID.nextRandom >>= either (ioError . userError) pure . parseNodeId . BSC.pack . UUID.toString)

-- Entropy is injected for embedded runtimes and deterministic collision tests;
-- the CLI always uses UUIDv4 generation, with no user-selected identity option.
createNodeWith :: IO NodeId -> FilePath -> Git IO -> FilePath -> FilePath -> IO (Either CreationFailure CreationResult)
createNodeWith generate executable git directory path = do
    installed <- newIORef False
    attempted <- newIORef False
    let observed =
            observeGit
                ( \invocation -> do
                    when ("worktree" `elem` gitArguments invocation && "add" `elem` gitArguments invocation) (writeIORef attempted True)
                )
                git
    outcome <- try $ withProtectedSession executable observed directory $ \session -> do
        prepared <- prepare
        case prepared of
            Left problem -> pure (Left problem)
            Right (common, format, node, rootOid, state, plan, target) -> do
                applied <- runExceptT $ do
                    current <- ExceptT (stateAt git common)
                    unless (managedRefs current == Map.delete node (managedRefs state)) (throwE "Node refs changed before creation")
                    -- Recheck paths before committing a new managed identity.
                    _ <- ExceptT (planDeploymentCandidateFor git common (managedRefs current) state (Set.singleton node) (deploymentRoot plan))
                    _ <- ExceptT (changeRef git common (managedRefs current) node rootOid False)
                    lift (writeIORef installed True)
                    ExceptT (addPlannedWorktree session plan node)
                    actual <- ExceptT (stateAt git common)
                    unless (managedRefs actual == managedRefs state) (throwE "Node refs changed during creation")
                    pure (CreationResult node rootOid target)
                case applied of
                    Right value -> pure (Right (Right value))
                    Left problem -> do
                        ownsRef <- readIORef installed
                        issued <- readIORef attempted
                        details <- compensate session common format node rootOid target ownsRef issued
                        pure (Right (Left (CreationFailure problem details)))
    pure $ case outcome of
        Left problem -> Left (CreationFailure (show (problem :: IOException)) ["Creation interrupted; inspect actual refs/worktrees. Existing objects are not deleted."])
        Right (Left problem) -> Left (CreationFailure problem [])
        Right (Right result) -> result
  where
    prepare = runExceptT $ do
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        before <- ExceptT (stateAt git common)
        node <- lift generate
        let uuid = nodeIdBytes node
        unless (BS.index uuid 14 == 52 && BS.index uuid 19 `elem` [56, 57, 97, 98]) (throwE "New Node identity must be UUIDv4")
        when (Map.member node (managedRefs before)) (throwE "Node UUID already exists locally")
        records <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
        when (any ((== Just node) . worktreeNode) records) (throwE "Node UUID is already checked out, including an unborn branch")
        refs <- ExceptT (query git common ["for-each-ref", "--format=%(refname)", "refs/remotes/", "refs/tags/"] "")
        when
            (any (\ref -> ref == "refs/tags/" <> uuid || ("refs/remotes/" `BS.isPrefixOf` ref && ("/" <> uuid) `BS.isSuffixOf` ref)) (BSC.lines refs))
            (throwE "Node UUID conflicts with an existing fetched identity or tag")
        config <- ExceptT (branchConfig git common node)
        unless (BS.null config) (throwE "Existing configuration for the proposed Node branch")
        preliminary <- ExceptT (planDeploymentCandidateFor git directory (managedRefs before) before Set.empty path)
        let root = deploymentRoot preliminary
            target = root </> shortName node
        either throwE pure (checkPathCollisions [(n, root </> shortName n) | n <- node : Map.keys (managedRefs before)])
        _ <- ExceptT (safeAbsolutePath target)
        occupied <- lift (doesPathExist target)
        when occupied (throwE "Node worktree target is occupied")
        -- Native Git validates configured author/committer identities before
        -- writing any objects or installing the branch.
        forM_ ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] $ \ident -> do
            _ <- ExceptT (query git common ["var", ident] "")
            pure ()
        let format = repositoryObjectFormat repository
            object args input = do
                bytes <- ExceptT (query git common args input)
                either throwE pure (maybe (Left "Invalid Git object response") (parseObjectId format) (BS.stripSuffix "\n" bytes))
        marker <- object ["hash-object", "-w", "--stdin"] ""
        inner <- object ["mktree", "-z"] ("100644 blob " <> objectIdBytes marker <> "\t.roam\0")
        top <- object ["mktree", "-z"] ("040000 tree " <> objectIdBytes inner <> "\t" <> uuid <> "\0")
        rootOid <- object ["commit-tree", BSC.unpack (objectIdBytes top), "-m", "Initialize Git-roam Node " ++ BSC.unpack uuid] ""
        state <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common (Map.insert node rootOid (managedRefs before))))
        final <- ExceptT (planDeploymentCandidateFor git common (managedRefs before) state (Set.singleton node) root)
        pure (common, format, node, rootOid, state, final, target)

    compensate session common format node rootOid target ownsRef issued = do
        outcome <- runExceptT $ do
            state <- ExceptT (stateAt git common)
            records <- ExceptT (listWorktrees git common format)
            bytes <- lift (encodePath target)
            let unchanged = Map.lookup node (managedRefs state) == Just rootOid
                matches = [r | r <- records, worktreeNode r == Just node, treePath r == bytes, not (treeMain r)]
            cleanup <-
                if ownsRef && issued && unchanged && length matches == 1
                    then do
                        plan <- lift (planRemovalFor git common state (Set.singleton node))
                        case plan of
                            Left problem -> pure ["New worktree retained: " ++ problem]
                            Right removal -> do
                                result <- lift (removePlannedWorktree session removal node)
                                pure (either (\problem -> ["Worktree compensation refused/failed: " ++ problem]) (const []) result)
                    else pure []
            actual <- ExceptT (stateAt git common)
            remaining <- ExceptT (listWorktrees git common format)
            config <- ExceptT (branchConfig git common node)
            when (ownsRef && Map.lookup node (managedRefs actual) == Just rootOid && BS.null config && all ((/= Just node) . worktreeNode) remaining) $ do
                _ <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common (Map.delete node (managedRefs actual))))
                _ <- ExceptT (changeRef git common (managedRefs actual) node rootOid True)
                pure ()
            final <- ExceptT (stateAt git common)
            finalRecords <- ExceptT (listWorktrees git common format)
            pure (cleanup ++ ["Actual managed refs: " ++ show (managedRefs final), "Remaining Node worktrees: " ++ show [(worktreeNode r, treePath r) | r <- finalRecords, worktreeNode r /= Nothing]])
        pure $ either (\problem -> ["Compensation stopped; inspect residual state: " ++ problem]) id outcome

changeRef :: Git IO -> FilePath -> Map.Map NodeId ObjectId -> NodeId -> ObjectId -> Bool -> IO (Either String BS.ByteString)
changeRef git directory stable node rootOid deleting = query git directory (ownHookBypass ++ ["update-ref", "--stdin"]) input
  where
    ref n = "refs/heads/" <> nodeIdBytes n
    input =
        BSC.unlines
            ( ["start"]
                ++ ["verify " <> ref n <> " " <> objectIdBytes oid | (n, oid) <- Map.toList stable, n /= node]
                ++ [(if deleting then "delete " else "create ") <> ref node <> " " <> objectIdBytes rootOid, "prepare", "commit"]
            )
