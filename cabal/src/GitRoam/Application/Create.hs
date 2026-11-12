{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module GitRoam.Application.Create (createNode, createNodeWith, createdBundlePath, CreationResult (..), CreationFailure (CreationFailure), creationFailureEvidence, creationFailureDiagnostic) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GitRoam.Application.Protection (ownHookBypass)
import GitRoam.Application.Validation (validateCandidate)
import GitRoam.Application.Worktree
import GitRoam.Diagnostic (Diagnostic (..), Evidence (..), Severity (..), emptyEvidence)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import qualified GitRoam.Git.Refs as Refs
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

-- A Node's checked-out payload lives below its linked worktree root.
createdBundlePath :: CreationResult -> FilePath
createdBundlePath result = createdPath result </> BSC.unpack (nodeIdBytes (createdNode result))

data CreationFailure = CreationFailureData String [String] (Maybe Evidence) Diagnostic deriving (Eq, Show)

pattern CreationFailure :: String -> [String] -> CreationFailure
pattern CreationFailure reason details <- CreationFailureData reason details _ _
    where
        CreationFailure reason details = CreationFailureData reason details Nothing (Diagnostic "creation_failed" Error (Text.pack reason))
{-# COMPLETE CreationFailure #-}

creationFailureEvidence :: CreationFailure -> Maybe Evidence
creationFailureEvidence (CreationFailureData _ _ evidence _) = evidence

creationFailureDiagnostic :: CreationFailure -> Diagnostic
creationFailureDiagnostic (CreationFailureData _ _ _ value) = value

withEvidence :: Evidence -> CreationFailure -> CreationFailure
withEvidence evidence (CreationFailureData reason details _ diagnosticValue) = CreationFailureData reason details (Just evidence) diagnosticValue

environment :: [(String, Maybe String)]
environment = readOnlyEnvironment ++ [(name, Nothing) | name <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    outcome <- runGit git (GitInvocation directory args input environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess && ("for-each-ref" `notElem` args || BS.null (gitStderr result)) -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

branchConfig :: Git IO -> FilePath -> NodeId -> IO (Either String BS.ByteString)
branchConfig git directory node = do
    outcome <- runGit git (GitInvocation directory ["config", "--local", "--get-regexp", "^branch\\." ++ BSC.unpack (nodeIdBytes node) ++ "\\."] "" environment)
    pure $ case outcome of
        Right result | gitExitCode result == ExitSuccess -> Right (gitStdout result)
        Right result | gitExitCode result == ExitFailure 1 -> Right ""
        other -> Left ("Cannot inspect branch configuration: " ++ show other)

createNode :: FilePath -> Git IO -> FilePath -> FilePath -> IO (Either CreationFailure CreationResult)
createNode = createNodeWith (UUID.nextRandom >>= either (ioError . userError) pure . parseNodeId . BSC.pack . UUID.toString)

-- The identity source is injected for embedded runtimes, caller-selected
-- identities and deterministic collision tests; only UUIDv4, Nil UUID and
-- Max UUID are admitted as new Node identities.
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
                    current <- ExceptT (loadOperationState git common)
                    unless (managedRefs current == Map.delete node (managedRefs state)) (throwE "Node refs changed before creation")
                    ExceptT (requireFreeName git common node)
                    -- Recheck paths before committing a new managed identity.
                    _ <- ExceptT (planDeploymentCandidateFor git common (managedRefs current) state (Set.singleton node) (deploymentRoot plan))
                    _ <- ExceptT (changeRef git common (managedRefs current) node rootOid False)
                    lift (writeIORef installed True)
                    ExceptT (addPlannedWorktree session plan node)
                    actual <- ExceptT (loadOperationState git common)
                    unless (managedRefs actual == managedRefs state) (throwE "Node refs changed during creation")
                    pure (CreationResult node rootOid target)
                case applied of
                    Right value -> pure (Right (Right value))
                    Left problem -> do
                        ownsRef <- readIORef installed
                        issued <- readIORef attempted
                        details <- compensate session common format node rootOid target ownsRef issued
                        pure (Right (Left (withEvidence (emptyEvidence{evidenceNode = Just node, evidenceCandidate = Just rootOid, evidenceRefConfirmed = Just ownsRef, evidenceAttempted = Just issued}) (CreationFailure problem details))))
    pure $ case outcome of
        Left problem -> Left (withEvidence emptyEvidence (CreationFailure (show (problem :: IOException)) ["Creation interrupted; inspect actual refs/worktrees. Existing objects are not deleted."]))
        Right (Left problem) -> Left (CreationFailure problem [])
        Right (Right result) -> result
  where
    prepare = runExceptT $ do
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        before <- ExceptT (loadOperationState git common)
        node <- lift generate
        let uuid = nodeIdBytes node
            isV4 = BS.index uuid 14 == 52 && BS.index uuid 19 `elem` [56, 57, 97, 98]
            isExtreme = uuid == "00000000-0000-0000-0000-000000000000" || uuid == "ffffffff-ffff-ffff-ffff-ffffffffffff"
        unless (isV4 || isExtreme) (throwE "New Node identity must be UUIDv4, Nil UUID or Max UUID")
        when (Map.member node (managedRefs before)) (throwE "Node UUID already exists locally")
        ExceptT (requireFreeName git common node)
        tagExists <- ExceptT (fmap (either (Left . show) Right) (Refs.refExists git common environment ("refs/tags/" <> uuid)))
        when tagExists (throwE "Node UUID conflicts with an existing tag")
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
            state <- ExceptT (loadOperationState git common)
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
            actual <- ExceptT (loadOperationState git common)
            remaining <- ExceptT (listWorktrees git common format)
            config <- ExceptT (branchConfig git common node)
            when (ownsRef && Map.lookup node (managedRefs actual) == Just rootOid && BS.null config && all ((/= Just node) . worktreeNode) remaining) $ do
                _ <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common (Map.delete node (managedRefs actual))))
                _ <- ExceptT (changeRef git common (managedRefs actual) node rootOid True)
                pure ()
            final <- ExceptT (loadOperationState git common)
            finalRecords <- ExceptT (listWorktrees git common format)
            pure (cleanup ++ ["Actual managed refs: " ++ show (managedRefs final), "Remaining Node worktrees: " ++ show [(worktreeNode r, treePath r) | r <- finalRecords, worktreeNode r /= Nothing]])
        pure $ either (\problem -> ["Compensation stopped; inspect residual state: " ++ problem]) id outcome

changeRef :: Git IO -> FilePath -> Map.Map NodeId ObjectId -> NodeId -> ObjectId -> Bool -> IO (Either String BS.ByteString)
changeRef git directory stable node rootOid deleting = query git directory (ownHookBypass ++ ["update-ref", "--no-deref", "--stdin"]) input
  where
    ref n = "refs/heads/" <> nodeIdBytes n
    input =
        BSC.unlines
            ( ["start"]
                ++ ["verify " <> ref n <> " " <> objectIdBytes oid | (n, oid) <- Map.toList stable, n /= node]
                ++ [(if deleting then "delete " else "create ") <> ref node <> " " <> objectIdBytes rootOid, "prepare", "commit"]
            )

requireFreeName :: Git IO -> FilePath -> NodeId -> IO (Either String ())
requireFreeName git directory node = do
    result <- Refs.refExists git directory environment ("refs/heads/" <> nodeIdBytes node)
    pure $ case result of
        Left problem -> Left (show problem)
        Right True -> Left "Node ref name is already occupied"
        Right False -> Right ()
