{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Inspect (
    InspectionError (..),
    InspectionReport (..),
    NodeView (..),
    WorktreeView (..),
    inspectState,
    inferNode,
    validateCandidate,
) where

import Control.Monad (foldM, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.Git.Objects
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository
import GitRoam.Repository
import System.Exit (ExitCode (..))

data InspectionError
    = RepositoryDiscoveryFailure RepositoryError
    | InspectionGitFailure [String] GitResult
    | InspectionTransportFailure [String] GitError
    | InvalidGitOutput [String] BS.ByteString
    | SymbolicNodeBranch NodeId BS.ByteString
    | NodeNotManaged NodeId
    | ShallowRepository
    | HistoryFailure HistoryError
    | MissingReachableObjects [BS.ByteString]
    | ReferencesChanged
    | CandidateStateInvalid [StateProblem]
    deriving (Eq, Show)

data WorktreeView = WorktreeView
    { worktreePath :: BS.ByteString
    , worktreeNode :: Maybe NodeId
    , worktreeIsMain :: Bool
    }
    deriving (Eq, Show)

data NodeView = NodeView
    { viewNode :: NodeId
    , viewTip :: ObjectId
    , viewKind :: CommitKind
    , viewLatestCheckpoint :: Maybe ObjectId
    , viewDependencies :: Map NodeId ObjectId
    , viewFormalCount :: Int
    }
    deriving (Eq, Show)

data InspectionReport = InspectionReport
    { reportNodes :: [NodeView]
    , reportProblems :: [StateProblem]
    , reportWorktrees :: [WorktreeView]
    , reportManagedState :: Either [StateProblem] ManagedState
    }
    deriving (Eq, Show)

inspectState :: Git IO -> FilePath -> [(String, Maybe String)] -> Maybe NodeId -> IO (Either InspectionError InspectionReport)
inspectState git directory environment target = do
    discovery <- inspectRepository git directory (environment ++ readOnlyEnvironment)
    case discovery of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository -> do
            provider <- cachedSource (nativeHistorySource git directory (repositoryObjectFormat repository) environment)
            runExceptT $ do
                before <- readRefs (repositoryObjectFormat repository)
                let beforeRefs = Map.map fst before
                -- Even a failed validation must distinguish a changing observation.
                outcome <- lift $ runExceptT $ do
                    shallow <- query ["rev-parse", "--is-shallow-repository"]
                    unless (shallow == "false\n") $
                        if shallow == "true\n"
                            then throwE ShallowRepository
                            else throwE (InvalidGitOutput ["rev-parse", "--is-shallow-repository"] shallow)
                    initial <- case target of
                        Nothing -> pure beforeRefs
                        Just node -> case Map.lookup node beforeRefs of
                            Just oid -> pure (Map.singleton node oid)
                            Nothing -> throwE (NodeNotManaged node)
                    (history, selected) <- closeSelection provider (repositoryObjectFormat repository) beforeRefs initial
                    case [(node, symbolic) | node <- Map.keys selected, Just (_, symbolic) <- [Map.lookup node before], not (BS.null symbolic)] of
                        (node, symbolic) : _ -> throwE (SymbolicNodeBranch node symbolic)
                        [] -> pure ()
                    connectivity (Map.elems selected)
                    worktrees <- query ["worktree", "list", "--porcelain", "-z"] >>= parseWorktrees
                    let validated = validateManagedState history selected
                        problems = either id (const []) validated
                    views <- mapM (nodeView history) (Map.toList selected)
                    pure (InspectionReport views problems worktrees validated)
                after <- readRefs (repositoryObjectFormat repository)
                unless (before == after) (throwE ReferencesChanged)
                either throwE pure outcome
  where
    query arguments = do
        outcome <- lift $ runGit git (GitInvocation directory ("--no-replace-objects" : arguments) BS.empty (environment ++ readOnlyEnvironment))
        case outcome of
            Left problem -> throwE (InspectionTransportFailure arguments problem)
            Right result
                | gitExitCode result == ExitSuccess
                , not (take 1 arguments == ["for-each-ref"] && not (BS.null (gitStderr result))) ->
                    pure (gitStdout result)
                | otherwise -> throwE (InspectionGitFailure arguments result)

    readRefs format = do
        let arguments = ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"]
        bytes <- query arguments
        pairs <- mapM (decodeRef format arguments) (BSC.lines bytes)
        pure (Map.fromList [pair | Just pair <- pairs])

    decodeRef format arguments row = case BS.split 0 row of
        [name, oid, symbolic] -> case BS.stripPrefix "refs/heads/" name >>= either (const Nothing) Just . parseNodeId of
            Nothing -> pure Nothing
            Just node -> do
                object <- either (const (throwE (InvalidGitOutput arguments row))) pure (parseObjectId format oid)
                pure (Just (node, (object, symbolic)))
        _ -> throwE (InvalidGitOutput arguments row)

    closeSelection provider format available selected = do
        outcome <- lift (validateHistory format provider (Map.elems selected))
        history <- either (throwE . HistoryFailure) pure outcome
        needed <- foldM (neededBy history) Set.empty (Map.elems selected)
        let expanded = Map.union selected (Map.restrictKeys available needed)
        if Map.keysSet expanded == Map.keysSet selected
            then pure (history, selected)
            else closeSelection provider format available expanded

    neededBy history needed tip = do
        versions <- either (const (throwE (InvalidGitOutput [] "Validated tip is absent"))) pure (formalHistory history tip)
        pure $
            Set.union needed $
                Set.unions
                    [ Map.keysSet (versionDependencies version)
                    | oid <- Set.toList versions
                    , Right (Just version) <- [projectCheckpoint history oid]
                    ]

    connectivity [] = pure ()
    connectivity tips = do
        bytes <- query (["rev-list", "--objects", "--no-object-names", "--missing=print"] ++ map (BSC.unpack . objectIdBytes) tips ++ ["--"])
        let missing = [BS.drop 1 row | row <- BSC.lines bytes, "?" `BS.isPrefixOf` row]
        unless (null missing) (throwE (MissingReachableObjects missing))

    nodeView history (node, tip) = do
        value <- maybe (throwE (InvalidGitOutput [] "Validated tip is absent")) pure (lookupCommit history tip)
        let latest = case validatedKind value of
                Root -> Nothing
                Checkpoint _ -> Just tip
                Content _ base -> case lookupCommit history base of
                    Just anchor | Checkpoint _ <- validatedKind anchor -> Just base
                    _ -> Nothing
            dependencies = case latest >>= either (const Nothing) id . projectCheckpoint history of
                Just version -> versionDependencies version
                Nothing -> Map.empty
            count = either (const 0) Set.size (formalHistory history tip)
        pure (NodeView node tip (validatedKind value) latest dependencies count)

    parseWorktrees bytes = mapM decode (zip [0 :: Int ..] (records (BS.split 0 bytes)))
      where
        records [] = []
        records ("" : rest) = records rest
        records fields = let (record, rest) = break BS.null fields in record : records rest
        decode (position, fields) = case fields of
            first : rest
                | Just path <- BS.stripPrefix "worktree " first
                , not (BS.null path) -> do
                    let branches = [name | field <- rest, Just name <- [BS.stripPrefix "branch refs/heads/" field]]
                        node = case branches of
                            [name] -> either (const Nothing) Just (parseNodeId name)
                            _ -> Nothing
                    pure (WorktreeView path node (position == 0))
            _ -> throwE (InvalidGitOutput ["worktree", "list"] bytes)

-- Inference is limited to an actual worktree on a canonical local Node branch.
inferNode :: Git IO -> FilePath -> IO (Either InspectionError (Maybe NodeId))
inferNode git directory = do
    found <- inspectRepository git directory readOnlyEnvironment
    case found of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository | Nothing <- repositoryWorktree repository -> pure (Right Nothing)
        Right _ -> do
            result <- runGit git (GitInvocation directory ["symbolic-ref", "-q", "HEAD"] BS.empty readOnlyEnvironment)
            pure $ case result of
                Left problem -> Left (InspectionTransportFailure ["symbolic-ref"] problem)
                Right value | gitExitCode value == ExitFailure 1 -> Right Nothing
                Right value | gitExitCode value /= ExitSuccess -> Left (InspectionGitFailure ["symbolic-ref"] value)
                Right value -> case BS.unsnoc (gitStdout value) of
                    Just (name, 10) -> Right (BS.stripPrefix "refs/heads/" name >>= either (const Nothing) Just . parseNodeId)
                    _ -> Left (InvalidGitOutput ["symbolic-ref"] (gitStdout value))

cachedSource :: HistorySource IO -> IO (HistorySource IO)
cachedSource provider = do
    commits <- newIORef Map.empty
    trees <- newIORef Map.empty
    let cached cache loader oid = do
            known <- Map.lookup oid <$> readIORef cache
            case known of
                Just value -> pure value
                Nothing -> do
                    value <- loader oid
                    modifyIORef' cache (Map.insert oid value)
                    pure value
    pure (HistorySource (cached commits (loadCommit provider)) (cached trees (loadTree provider)))

-- A caller-supplied final ref set; no ref writes or claim of a live snapshot.
validateCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either InspectionError ManagedState)
validateCandidate git directory refs = runExceptT $ do
    discovered <- lift (inspectRepository git directory readOnlyEnvironment)
    repository <- either (throwE . RepositoryDiscoveryFailure) pure discovered
    let format = repositoryObjectFormat repository
    loaded <- lift (validateHistory format (nativeHistorySource git directory format []) (Map.elems refs))
    history <- either (throwE . HistoryFailure) pure loaded
    unless (Map.null refs) $ do
        let arguments =
                ["--no-replace-objects", "rev-list", "--objects", "--no-object-names", "--missing=print"]
                    ++ map (BSC.unpack . objectIdBytes) (Map.elems refs)
                    ++ ["--"]
        outcome <- lift (runGit git (GitInvocation directory arguments BS.empty readOnlyEnvironment))
        result <- either (throwE . InspectionTransportFailure arguments) pure outcome
        unless (gitExitCode result == ExitSuccess) (throwE (InspectionGitFailure arguments result))
        let missing = [BS.drop 1 row | row <- BSC.lines (gitStdout result), "?" `BS.isPrefixOf` row]
        unless (null missing) (throwE (MissingReachableObjects missing))
    either (throwE . CandidateStateInvalid) pure (validateManagedState history refs)
