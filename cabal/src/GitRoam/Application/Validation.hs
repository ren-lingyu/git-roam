{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Validation (
    ValidationError (..),
    ValidationEvidence,
    validationRepository,
    ValidationObservation (..),
    observeManagedState,
    withValidationEvidence,
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
import GitRoam.Protocol.Objects (HistorySource)
import GitRoam.Protocol.Repository
import GitRoam.Repository
import System.Exit (ExitCode (..))

data ValidationError
    = RepositoryDiscoveryFailure RepositoryError
    | ValidationGitFailure [String] GitResult
    | ValidationTransportFailure [String] GitError
    | InvalidGitOutput [String] BS.ByteString
    | SymbolicNodeBranch NodeId BS.ByteString
    | ShallowRepository
    | HistoryFailure HistoryError
    | MissingReachableObjects [ObjectId]
    | ReferencesChanged
    | CandidateStateInvalid [StateProblem]
    deriving (Eq, Show)

-- Read-only projection evidence. A trusted state is returned only after the
-- projection, identity validation, final ref comparison and session completion.
newtype ValidationEvidence = ValidationEvidence
    { validationRepository :: Repository
    }
    deriving (Eq, Show)

data ValidationObservation = ValidationObservation
    { validationInitialRefs :: Maybe (Map NodeId ObjectId)
    , validationOutcome :: Either ValidationError ManagedState
    }
    deriving (Eq, Show)

observeManagedState :: Git IO -> FilePath -> IO (Either ValidationError ValidationObservation)
observeManagedState git directory = observeWithEvidence git directory [] (const (pure (Right ())))

withValidationEvidence :: Git IO -> FilePath -> [(String, Maybe String)] -> (ValidationEvidence -> IO (Either ValidationError ())) -> IO (Either ValidationError ManagedState)
withValidationEvidence git directory environment project = do
    observed <- observeWithEvidence git directory environment project
    pure (observed >>= validationOutcome)

loadManagedState :: Git IO -> FilePath -> IO (Either ValidationError ManagedState)
loadManagedState git directory = withValidationEvidence git directory [] (const (pure (Right ())))

observeWithEvidence :: Git IO -> FilePath -> [(String, Maybe String)] -> (ValidationEvidence -> IO (Either ValidationError ())) -> IO (Either ValidationError ValidationObservation)
observeWithEvidence git directory environment project = do
    discovered <- inspectRepository git directory (environment ++ readOnlyEnvironment)
    case discovered of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository -> do
            initial <- readRefs repository
            case initial of
                Left problem -> pure (Right (ValidationObservation Nothing (Left problem)))
                Right before -> do
                    let refs = Map.map fst before
                    -- Capture initial refs before even starting the raw session.
                    completed <- withHistorySource git directory (repositoryObjectFormat repository) environment $ \source -> do
                        provisional <- case [(node, target) | (node, (_, target)) <- Map.toAscList before, not (BS.null target)] of
                            (node, target) : _ -> pure (Left (SymbolicNodeBranch node target))
                            [] -> validateStatic git directory environment repository source refs project
                        after <- readRefs repository
                        pure $ case after of
                            Left problem -> Left problem
                            Right current | current /= before -> Left ReferencesChanged
                            Right _ -> provisional
                    let final = either (Left . ValidationTransportFailure ["cat-file", "--batch"]) id completed
                    pure (Right (ValidationObservation (Just refs) final))
  where
    readRefs repository = do
        let arguments = Refs.nodeRefArguments Refs.LocalNodes
        observed <- Refs.readNodeRefs git directory (environment ++ readOnlyEnvironment) (repositoryObjectFormat repository) Refs.LocalNodes
        pure $ do
            records <- either (Left . failure arguments) Right (Refs.requireCompleteRefs observed)
            pure (Map.fromList [(Refs.observedNode record, (Refs.observedTip record, Refs.observedSymbolic record)) | record <- records])
    failure arguments problem = case problem of
        Refs.RefTransportFailure value -> ValidationTransportFailure arguments value
        Refs.RefCommandFailure value -> ValidationGitFailure arguments value
        Refs.MalformedRefOutput row -> InvalidGitOutput arguments row
        Refs.InvalidRefObject row _ -> InvalidGitOutput arguments row
        Refs.DuplicateNodeRef row -> InvalidGitOutput arguments row

-- Single static protocol acceptance path for actual and candidate state.
-- Candidate callers provide refs; no live-ref enumeration is hidden here.
validateStatic :: Git IO -> FilePath -> [(String, Maybe String)] -> Repository -> HistorySource IO -> Map NodeId ObjectId -> (ValidationEvidence -> IO (Either ValidationError ())) -> IO (Either ValidationError ManagedState)
validateStatic git directory environment repository source refs project = runExceptT $ do
    shallow <- ExceptT (validationQuery git directory environment ["rev-parse", "--is-shallow-repository"])
    case shallow of
        "false\n" -> pure ()
        "true\n" -> throwE ShallowRepository
        _ -> throwE (InvalidGitOutput ["rev-parse", "--is-shallow-repository"] shallow)
    loaded <- lift (validateHistory (repositoryObjectFormat repository) source (Map.elems refs))
    history <- either (throwE . HistoryFailure) pure loaded
    connected <- lift (checkStoredConnectivity git directory environment source (Map.elems refs))
    missing <- either (throwE . HistoryFailure . uncurry ObjectUnavailable) pure connected
    unless (null missing) (throwE (MissingReachableObjects missing))
    ExceptT (project (ValidationEvidence repository))
    either (throwE . CandidateStateInvalid) pure (validateManagedState history refs)

validateCandidate :: Git IO -> FilePath -> Map NodeId ObjectId -> IO (Either ValidationError ManagedState)
validateCandidate git directory refs = do
    discovered <- inspectRepository git directory readOnlyEnvironment
    case discovered of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository -> do
            result <- withHistorySource git directory (repositoryObjectFormat repository) [] $ \source ->
                validateStatic git directory [] repository source refs (const (pure (Right ())))
            pure (either (Left . ValidationTransportFailure ["cat-file", "--batch"]) id result)

validationQuery :: Git IO -> FilePath -> [(String, Maybe String)] -> [String] -> IO (Either ValidationError BS.ByteString)
validationQuery git directory environment arguments = do
    outcome <- runGit git (GitInvocation directory ("--no-replace-objects" : arguments) BS.empty (environment ++ readOnlyEnvironment))
    pure $ case outcome of
        Left problem -> Left (ValidationTransportFailure arguments problem)
        Right result | gitExitCode result == ExitSuccess && BS.null (gitStderr result) -> Right (gitStdout result)
        Right result -> Left (ValidationGitFailure arguments result)

inferNode :: Git IO -> FilePath -> IO (Either ValidationError (Maybe NodeId))
inferNode git directory = do
    found <- inspectRepository git directory readOnlyEnvironment
    case found of
        Left problem -> pure (Left (RepositoryDiscoveryFailure problem))
        Right repository | Nothing <- repositoryWorktree repository -> pure (Right Nothing)
        Right _ -> do
            result <- runGit git (GitInvocation directory ["symbolic-ref", "-q", "HEAD"] BS.empty readOnlyEnvironment)
            pure $ case result of
                Left problem -> Left (ValidationTransportFailure ["symbolic-ref"] problem)
                Right value | gitExitCode value == ExitFailure 1 -> Right Nothing
                Right value | gitExitCode value /= ExitSuccess -> Left (ValidationGitFailure ["symbolic-ref"] value)
                Right value -> case BS.unsnoc (gitStdout value) of
                    Just (name, 10) -> Right (BS.stripPrefix "refs/heads/" name >>= either (const Nothing) Just . parseNodeId)
                    _ -> Left (InvalidGitOutput ["symbolic-ref"] (gitStdout value))
