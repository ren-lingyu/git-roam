{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Checkpoint (checkpoint, DependencyEdits (..), CheckpointResult (..), CheckpointFailure (..)) where

import Control.Exception (IOException, try)
import Control.Monad (forM, forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Inspect (inferNode, inspectState, reportManagedState, validateCandidate)
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import GitRoam.Application.Worktree (withProtectedSession)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment, resolveCommitReference)
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Exit (ExitCode (..))

data DependencyEdits = DependencyEdits
    { clearDependencies :: Bool
    , dropDependencies :: [NodeId]
    , dependencyRevisions :: [String]
    }
    deriving (Eq, Show)
data CheckpointResult = CheckpointResult
    { checkpointNode :: NodeId
    , checkpointOid :: ObjectId
    , checkpointContent :: ObjectId
    , checkpointDependencies :: Map.Map NodeId ObjectId
    }
    deriving (Eq, Show)
data CheckpointFailure = CheckpointFailure String [String] deriving (Eq, Show)

-- Only shared-validator output enters construction. No index/tree snapshot is
-- used; q, optional existing w and tree are derived from the validated tip.
data Plan = Plan ManagedState NodeId ObjectId ObjectId (Maybe ObjectId) ObjectId (Map.Map NodeId ObjectId)

environment :: [(String, Maybe String)]
environment = readOnlyEnvironment ++ [(name, Nothing) | name <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    outcome <- runGit git (GitInvocation directory args input environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess && ("rev-parse" `notElem` args || BS.null (gitStderr result)) -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

stateAt :: Git IO -> FilePath -> IO (Either String ManagedState)
stateAt git directory = do
    outcome <- inspectState git directory [] Nothing
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right report -> either (Left . show) Right (reportManagedState report)

messageValid :: BS.ByteString -> Either String ()
messageValid bytes = do
    text <- either (const (Left "Checkpoint message must be UTF-8")) Right (Encoding.decodeUtf8' bytes)
    unless (not (Text.null (Text.strip text)) && not (BS.elem 0 bytes)) (Left "Checkpoint message must be nonempty text without NUL bytes")

checkpoint :: FilePath -> Git IO -> FilePath -> Maybe NodeId -> BS.ByteString -> DependencyEdits -> IO (Either CheckpointFailure CheckpointResult)
checkpoint executable git directory requested message edits = do
    candidate <- newIORef Nothing
    installed <- newIORef False
    outcome <- try $ withProtectedSession executable git directory $ \_ -> runExceptT $ do
        either throwE pure (messageValid message)
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        node <- case requested of
            Just value -> pure value
            Nothing -> do
                inferred <- ExceptT (fmap (either (Left . show) Right) (inferNode git directory))
                maybe (throwE "Select --node UUID or run inside a Node worktree") pure inferred
        before <- ExceptT (stateAt git common)
        plan <- ExceptT (prepare git common (repositoryObjectFormat repository) before node edits)
        let Plan _ _ old q editing tree dependencies = plan
            object args input = do
                bytes <- ExceptT (query git common args input)
                either throwE pure (maybe (Left "Invalid commit-tree response") (parseObjectId (repositoryObjectFormat repository)) (BS.stripSuffix "\n" bytes))
            commit parents text = object (["-c", "i18n.commitEncoding=UTF-8", "commit-tree", BSC.unpack (objectIdBytes tree)] ++ concatMap (\oid -> ["-p", BSC.unpack (objectIdBytes oid)]) parents ++ ["-F", "-"]) text
        forM_ ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] $ \ident -> do
            _ <- ExceptT (query git common ["var", ident] "")
            pure ()
        content <- case editing of
            Just oid -> pure oid
            Nothing -> commit [q] "Record unchanged content before Checkpoint\n"
        oid <- commit (q : content : Map.elems dependencies) message
        let result = CheckpointResult node oid content dependencies
        lift (writeIORef candidate (Just result))
        target <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git common (Map.insert node oid (managedRefs before))))
        either (throwE . show) pure (validateOrdinaryTransition before target)
        current <- ExceptT (stateAt git common)
        unless (managedRefs current == managedRefs before) (throwE "Node refs changed before Checkpoint installation")
        -- All checked-out index/worktree states remain valid: the new tip has
        -- exactly the old tip's tree. The branch advances once, conditionally.
        let ref n = "refs/heads/" <> nodeIdBytes n
            input =
                BSC.unlines
                    ( ["start"]
                        ++ ["verify " <> ref n <> " " <> objectIdBytes value | (n, value) <- Map.toList (managedRefs before), n /= node]
                        ++ ["update " <> ref node <> " " <> objectIdBytes oid <> " " <> objectIdBytes old, "prepare", "commit"]
                    )
        _ <- ExceptT (query git common (ownHookBypass ++ ["update-ref", "--stdin"]) input)
        lift (writeIORef installed True)
        actual <- ExceptT (stateAt git common)
        unless (managedRefs actual == managedRefs target) (throwE "Node refs changed after Checkpoint installation")
        ExceptT (requireProtectionFor executable common)
        pure result
    case outcome of
        Right (Right result) -> pure (Right result)
        other -> do
            proposed <- readIORef candidate
            advanced <- readIORef installed
            let reason = case other of
                    Left problem -> show (problem :: IOException)
                    Right (Left problem) -> problem
                details = case proposed of
                    Nothing -> []
                    Just value ->
                        [ "Node: " ++ show (checkpointNode value)
                        , "Candidate Checkpoint: " ++ show (checkpointOid value)
                        , "Selected Content: " ++ show (checkpointContent value)
                        , if advanced
                            then "Ref update completed before follow-up failure; no history rollback was attempted."
                            else "Object construction does not prove ref installation; inspect actual refs. No history rollback was attempted."
                        ]
            pure (Left (CheckpointFailure reason details))

prepare :: Git IO -> FilePath -> ObjectFormat -> ManagedState -> NodeId -> DependencyEdits -> IO (Either String Plan)
prepare git directory format state node edits = runExceptT $ do
    old <- maybe (throwE "No managed branch for the selected Node") pure (Map.lookup node (managedRefs state))
    let history = managedHistory state
    tip <- maybe (throwE "Validated Node tip is unavailable") pure (lookupCommit history old)
    (q, editing) <- case validatedKind tip of
        Root -> throwE "Commit Content with ordinary Git before the first Checkpoint (an empty Content commit is allowed)"
        Content _ base -> pure (base, Just old)
        Checkpoint _ -> pure (old, Nothing)
    anchor <- maybe (throwE "Validated Content base is unavailable") pure (lookupCommit history q)
    inherited <- case validatedKind anchor of
        Root -> pure Map.empty
        Checkpoint parents -> pure (directDependencies parents)
        _ -> throwE "Content base must be Root or Checkpoint"
    let drops = dropDependencies edits
    when (length drops /= Set.size (Set.fromList drops)) (throwE "Duplicate dependency removal")
    when (clearDependencies edits && not (null drops)) (throwE "Do not combine --clear-dependencies with --drop-dependency")
    let base = if clearDependencies edits then Map.empty else inherited
    forM_ drops $ \dep -> unless (Map.member dep base) (throwE ("No inherited dependency to remove: " ++ show dep))
    additions <- forM (dependencyRevisions edits) $ \revision -> do
        oid <- ExceptT (resolveCommitReference git directory format environment revision)
        value <- maybe (throwE "Dependency must be a Checkpoint retained by a local Node branch") pure (lookupCommit history oid)
        case validatedKind value of
            Checkpoint _ -> pure ()
            _ -> throwE "Root and Content cannot be knowledge dependencies"
        let dep = validatedNode value
        when (dep == node) (throwE "A knowledge dependency must belong to another Node; this command does not merge formal histories")
        unless (maybe False (Set.member oid) (Map.lookup dep (retainedCheckpoints state))) (throwE "Dependency version is not retained by its Node branch")
        when (dep `elem` drops) (throwE "Do not both remove and replace the same dependency")
        pure (dep, oid)
    when (length additions /= Map.size (Map.fromList additions)) (throwE "Specify at most one dependency version per external Node")
    let dependencies = Map.union (Map.fromList additions) (Map.withoutKeys base (Set.fromList drops))
    pure (Plan state node old q editing (validatedTree tip) dependencies)
