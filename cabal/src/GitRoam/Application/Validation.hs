{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Validation (
    ValidationError (..),
    ValidationEvidence,
    validationRepository,
    validationHistory,
    validationRefs,
    withValidationEvidence,
    validateEvidence,
    loadManagedState,
    validateCandidate,
    inferNode,
    validationQuery,
) where

import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import GitRoam.Git
import GitRoam.Git.Objects
import qualified GitRoam.Git.Refs as Refs
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import System.Exit (ExitCode (..))

data ValidationError
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

-- Complete object/history evidence, not a CLI report or partial ManagedState.
-- Branch identity still needs validateEvidence before any mutation may use it.
data ValidationEvidence = ValidationEvidence
    { validationRepository :: Repository
    , validationHistory :: ValidatedHistory
    , validationRefs :: Map NodeId ObjectId
    }
    deriving (Eq, Show)

validateEvidence :: ValidationEvidence -> Either ValidationError ManagedState
validateEvidence evidence =
    either
        (Left . CandidateStateInvalid)
        Right
        (validateManagedState (validationHistory evidence) (validationRefs evidence))

-- The projection may perform additional READ-ONLY observations/preflight. Keep
-- them inside the ref snapshot and strict raw-session lifetime. Exceptions are
-- not converted to successful evidence, nor are lifecycle failures accepted.
withValidationEvidence :: Git IO -> FilePath -> [(String, Maybe String)] -> Maybe NodeId -> (ValidationEvidence -> IO (Either ValidationError a)) -> IO (Either ValidationError a)
withValidationEvidence git directory environment target project = do
    discovery <- inspectRepository git directory (environment ++ readOnlyEnvironment)
    case discovery of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository -> do
            result <- withHistorySource git directory (repositoryObjectFormat repository) environment $ \provider -> runExceptT $ do
                before <- readRefs (repositoryObjectFormat repository)
                let beforeRefs = Map.map fst before
                -- Changing refs take precedence over provisional read failures.
                outcome <- lift $ runExceptT $ do
                    shallow <- ExceptT (validationQuery git directory environment ["rev-parse", "--is-shallow-repository"])
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
                    connectivity <- lift (checkStoredConnectivity git directory environment provider (Map.elems selected))
                    missing <- either (throwE . HistoryFailure . uncurry ObjectUnavailable) pure connectivity
                    unless (null missing) (throwE (MissingReachableObjects (map objectIdBytes missing)))
                    ExceptT (project (ValidationEvidence repository history selected))
                after <- readRefs (repositoryObjectFormat repository)
                unless (before == after) (throwE ReferencesChanged)
                either throwE pure outcome
            pure (either (Left . InspectionTransportFailure ["cat-file", "--batch"]) id result)
  where
    readRefs format = do
        let arguments = Refs.nodeRefArguments Refs.LocalNodes
        observed <- lift (Refs.readNodeRefs git directory (environment ++ readOnlyEnvironment) format Refs.LocalNodes)
        records <- either (throwE . failure arguments) pure (Refs.requireCompleteRefs observed)
        pure (Map.fromList [(Refs.observedNode record, (Refs.observedTip record, Refs.observedSymbolic record)) | record <- records])
    failure arguments problem = case problem of
        Refs.RefTransportFailure value -> InspectionTransportFailure arguments value
        Refs.RefCommandFailure value -> InspectionGitFailure arguments value
        Refs.MalformedRefOutput row -> InvalidGitOutput arguments row
        Refs.InvalidRefObject row _ -> InvalidGitOutput arguments row
        Refs.DuplicateNodeRef row -> InvalidGitOutput arguments row

-- Direct whole-local-set loader. No worktree or presentation work is implicit.
loadManagedState :: Git IO -> FilePath -> IO (Either ValidationError ManagedState)
loadManagedState git directory = withValidationEvidence git directory [] Nothing (pure . validateEvidence)

-- Required Git reads retain the established diagnostic constructors/categories.
validationQuery :: Git IO -> FilePath -> [(String, Maybe String)] -> [String] -> IO (Either ValidationError BS.ByteString)
validationQuery git directory environment arguments = do
    outcome <- runGit git (GitInvocation directory ("--no-replace-objects" : arguments) BS.empty (environment ++ readOnlyEnvironment))
    pure $ case outcome of
        Left problem -> Left (InspectionTransportFailure arguments problem)
        Right result | gitExitCode result == ExitSuccess -> Right (gitStdout result)
        Right result -> Left (InspectionGitFailure arguments result)

-- Infer a Node from the current worktree when its symbolic HEAD names a
-- canonical local Node branch. Detached HEADs and ordinary branches do not
-- imply a Node identity.
inferNode :: Git IO -> FilePath -> IO (Either ValidationError (Maybe NodeId))
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

-- Validate an explicitly supplied candidate ref set. Its history may include
-- context commits no longer retained by any current local Node branch.
-- This function never observes or modifies the live managed ref set.
validateCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either ValidationError ManagedState)
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
