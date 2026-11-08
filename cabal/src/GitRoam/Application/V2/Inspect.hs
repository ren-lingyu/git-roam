{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

-- Read-only integration of the context protocol with stored Git objects.
-- Production commands continue to use Application.Inspect until cutover.
module GitRoam.Application.V2.Inspect (
    InspectionError (..),
    InspectionReport (..),
    NodeView (..),
    WorktreeView (..),
    inspectState,
    validateCandidate,
) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import GitRoam.Git
import GitRoam.Git.Objects
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.V2.History
import GitRoam.Protocol.V2.Repository
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
    , viewContextParents :: [ObjectId]
    , viewCheckpointCount :: Int
    }
    deriving (Eq, Show)

data InspectionReport = InspectionReport
    { reportNodes :: [NodeView]
    , reportProblems :: [StateProblem]
    , reportWorktrees :: [WorktreeView]
    , reportManagedState :: Either [StateProblem] ManagedState
    }
    deriving (Eq, Show)

-- Read only the selected local branch tips and their Git ancestor closure.
-- Unlike v0.1.0, external context never expands the managed ref selection.
inspectState :: Git IO -> FilePath -> [(String, Maybe String)] -> Maybe NodeId -> IO (Either InspectionError InspectionReport)
inspectState git directory environment target = do
    discovery <- inspectRepository git directory (environment ++ readOnlyEnvironment)
    case discovery of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository -> do
            result <- withHistorySource git directory (repositoryObjectFormat repository) environment $ \provider -> runExceptT $ do
                before <- readRefs (repositoryObjectFormat repository)
                let beforeRefs = Map.map fst before
                -- A changing ref observation takes precedence over failures
                -- from the provisional view of the repository.
                outcome <- lift $ runExceptT $ do
                    shallow <- query ["rev-parse", "--is-shallow-repository"]
                    unless (shallow == "false\n") $
                        if shallow == "true\n"
                            then throwE ShallowRepository
                            else throwE (InvalidGitOutput ["rev-parse", "--is-shallow-repository"] shallow)
                    selected <- case target of
                        Nothing -> pure beforeRefs
                        Just node -> case Map.lookup node beforeRefs of
                            Just oid -> pure (Map.singleton node oid)
                            Nothing -> throwE (NodeNotManaged node)
                    case [(node, symbolic) | node <- Map.keys selected, Just (_, symbolic) <- [Map.lookup node before], not (BS.null symbolic)] of
                        (node, symbolic) : _ -> throwE (SymbolicNodeBranch node symbolic)
                        [] -> pure ()
                    loaded <- lift (validateHistory (repositoryObjectFormat repository) provider (Map.elems selected))
                    history <- either (throwE . HistoryFailure) pure loaded
                    connectivity provider (Map.elems selected)
                    worktrees <- query ["worktree", "list", "--porcelain", "-z"] >>= parseWorktrees (repositoryObjectFormat repository)
                    let validated = validateManagedState history selected
                        problems = either id (const []) validated
                    views <- mapM (nodeView history) (Map.toList selected)
                    pure (InspectionReport views problems worktrees validated)
                after <- readRefs (repositoryObjectFormat repository)
                unless (before == after) (throwE ReferencesChanged)
                either throwE pure outcome
            pure (either (Left . InspectionTransportFailure ["cat-file", "--batch"]) id result)
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

    connectivity provider tips = do
        outcome <- lift (checkStoredConnectivity git directory environment provider tips)
        missing <- either (throwE . HistoryFailure . uncurry ObjectUnavailable) pure outcome
        unless (null missing) (throwE (MissingReachableObjects (map objectIdBytes missing)))

    nodeView history (node, tip) = do
        value <- maybe (throwE (InvalidGitOutput [] "Validated tip is absent")) pure (lookupCommit history tip)
        firstParents <- either (const (throwE (InvalidGitOutput [] "First-parent history is unavailable"))) pure (firstParentHistory history tip)
        let checkpoints =
                [ oid
                | oid <- firstParents
                , Just ancestor <- [lookupCommit history oid]
                , Checkpoint _ _ <- [validatedKind ancestor]
                ]
            latest = case checkpoints of
                oid : _ -> Just oid
                [] -> Nothing
        context <- case latest of
            Nothing -> pure []
            Just oid -> either (const (throwE (InvalidGitOutput [] "Checkpoint context is unavailable"))) pure (contextParents history oid)
        pure (NodeView node tip (validatedKind value) latest context (length checkpoints))

    parseWorktrees format bytes = case Worktrees.decodeWorktrees format bytes of
        Left _ -> throwE (InvalidGitOutput ["worktree", "list"] bytes)
        Right records -> pure [WorktreeView (Worktrees.treePath r) (Worktrees.worktreeNode r) (Worktrees.treeMain r) | r <- records]

-- Validate an explicitly supplied candidate ref set. Its history may include
-- context commits no longer retained by any current local Node branch.
-- This function never observes or modifies the live managed ref set.
validateCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either InspectionError ManagedState)
validateCandidate git directory refs = runExceptT $ do
    discovered <- lift (inspectRepository git directory readOnlyEnvironment)
    repository <- either (throwE . RepositoryDiscoveryFailure) pure discovered
    let format = repositoryObjectFormat repository
        arguments = ["rev-parse", "--is-shallow-repository"]
    observed <- lift (runGit git (GitInvocation directory arguments BS.empty readOnlyEnvironment))
    result <- either (throwE . InspectionTransportFailure arguments) pure observed
    unless (gitExitCode result == ExitSuccess) (throwE (InspectionGitFailure arguments result))
    case gitStdout result of
        "false\n" -> pure ()
        "true\n" -> throwE ShallowRepository
        bytes -> throwE (InvalidGitOutput arguments bytes)
    validated <- lift $ withHistorySource git directory format [] $ \provider -> runExceptT $ do
        loaded <- lift (validateHistory format provider (Map.elems refs))
        history <- either (throwE . HistoryFailure) pure loaded
        outcome <- lift (checkStoredConnectivity git directory [] provider (Map.elems refs))
        missing <- either (throwE . HistoryFailure . uncurry ObjectUnavailable) pure outcome
        unless (null missing) (throwE (MissingReachableObjects (map objectIdBytes missing)))
        either (throwE . CandidateStateInvalid) pure (validateManagedState history refs)
    either (throwE . InspectionTransportFailure ["cat-file", "--batch"]) (either throwE pure) validated
