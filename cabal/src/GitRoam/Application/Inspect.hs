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
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.Git.Objects
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
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
            result <- withHistorySource git directory (repositoryObjectFormat repository) environment $ \provider -> runExceptT $ do
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

    connectivity provider tips = do
        outcome <- lift (checkStoredConnectivity git directory environment provider tips)
        missing <- either (throwE . HistoryFailure . uncurry ObjectUnavailable) pure outcome
        unless (null missing) (throwE (MissingReachableObjects (map objectIdBytes missing)))

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

    parseWorktrees format bytes = case Worktrees.decodeWorktrees format bytes of
        Left _ -> throwE (InvalidGitOutput ["worktree", "list"] bytes)
        Right records -> pure [WorktreeView (Worktrees.treePath r) (Worktrees.worktreeNode r) (Worktrees.treeMain r) | r <- records]

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

-- A caller-supplied final ref set; no ref writes or claim of a live snapshot.
validateCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either InspectionError ManagedState)
validateCandidate git directory refs = runExceptT $ do
    discovered <- lift (inspectRepository git directory readOnlyEnvironment)
    repository <- either (throwE . RepositoryDiscoveryFailure) pure discovered
    let format = repositoryObjectFormat repository
    let arguments = ["rev-parse", "--is-shallow-repository"]
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
