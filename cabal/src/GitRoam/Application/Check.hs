{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Check (
    CheckConclusion (..),
    CheckDiagnostic (..),
    CheckReport (..),
    checkManagedState,
    conclusionFor,
) where

import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as Text
import GitRoam.Application.Validation
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import GitRoam.Protocol.Repository

data CheckConclusion = Valid | Invalid | Inconclusive deriving (Eq, Show)

data CheckDiagnostic = CheckDiagnostic
    { checkCode :: Text
    , checkMessage :: Text
    , checkNode :: Maybe NodeId
    , checkObject :: Maybe ObjectId
    }
    deriving (Eq, Show)

data CheckReport = CheckReport
    { checkConclusion :: CheckConclusion
    , checkRefs :: Maybe (Map NodeId ObjectId)
    , checkDiagnostics :: [CheckDiagnostic]
    }
    deriving (Eq, Show)

-- Output selection never participates in validation. The refs are the captured
-- input, not a later reconstruction or a claim of current/valid branch values.
checkManagedState :: Git IO -> FilePath -> IO (Either ValidationError CheckReport)
checkManagedState git directory = do
    observed <- observeManagedState git directory
    pure $ fmap report observed
  where
    report value = case validationOutcome value of
        Right _ -> CheckReport Valid (validationInitialRefs value) []
        Left problem -> CheckReport (conclusionFor problem) (validationInitialRefs value) (diagnosticsFor problem)

conclusionFor :: ValidationError -> CheckConclusion
conclusionFor problem = case problem of
    SymbolicNodeBranch _ _ -> Invalid
    HistoryFailure (ObjectUnavailable _ reason) -> case reason of
        MissingObject -> Invalid
        WrongObjectType _ -> Invalid
        MalformedObject _ -> Invalid
        IncompleteHistory _ -> Inconclusive
        ObjectReadFailure _ -> Inconclusive
    HistoryFailure _ -> Invalid
    MissingReachableObjects values -> if null values then Inconclusive else Invalid
    CandidateStateInvalid problems
        | null problems || any unknown problems -> Inconclusive
        | otherwise -> Invalid
    _ -> Inconclusive
  where
    unknown (UnknownNodeTip _ _) = True
    unknown _ = False

diagnosticsFor :: ValidationError -> [CheckDiagnostic]
diagnosticsFor problem = case problem of
    CandidateStateInvalid values | not (null values) -> map state values
    MissingReachableObjects values | not (null values) -> [CheckDiagnostic "objects_missing" "Required stored object is missing" Nothing (Just oid) | oid <- values]
    _ -> [single]
  where
    basic code = CheckDiagnostic code (Text.pack (show problem)) Nothing Nothing
    state value = case value of
        UnknownNodeTip node oid -> CheckDiagnostic "internal_evidence_incomplete" "Validated history does not contain a required tip" (Just node) (Just oid)
        RefIdentityMismatch node actual oid -> CheckDiagnostic "identity_mismatch" ("Node branch points to another Node's history: " <> Text.pack (show actual)) (Just node) (Just oid)
    single = case problem of
        RepositoryDiscoveryFailure _ -> basic "repository_discovery_failed"
        ValidationGitFailure _ _ -> basic "git_read_failed"
        ValidationTransportFailure _ _ -> basic "git_transport_failed"
        InvalidGitOutput _ _ -> basic "invalid_git_output"
        SymbolicNodeBranch node _ -> (basic "symbolic_node_branch"){checkNode = Just node}
        ShallowRepository -> basic "history_incomplete"
        ReferencesChanged -> basic "observation_changed"
        MissingReachableObjects _ -> basic "objects_missing"
        CandidateStateInvalid _ -> basic "internal_evidence_incomplete"
        HistoryFailure reason -> case reason of
            ObjectUnavailable oid detail -> (basic (objectCode detail)){checkObject = Just oid}
            ObjectFormatMismatch oid -> (basic "object_format_mismatch"){checkObject = Just oid}
            InvalidNodeTree oid _ -> (basic "node_tree_invalid"){checkObject = Just oid}
            DuplicateParents oid -> (basic "duplicate_parents"){checkObject = Just oid}
            IdentityChanged oid node _ -> (basic "identity_changed"){checkNode = Just node, checkObject = Just oid}
            ConflictingRoots node oid _ -> (basic "root_conflict"){checkNode = Just node, checkObject = Just oid}
            CheckpointTreeMismatch oid _ -> (basic "checkpoint_tree_mismatch"){checkObject = Just oid}
            OverlappingContextTree oid _ -> (basic "context_overlap"){checkObject = Just oid}
            CyclicHistory oid -> (basic "history_cycle"){checkObject = Just oid}
    objectCode reason = case reason of
        MissingObject -> "object_missing"
        WrongObjectType _ -> "object_type_mismatch"
        MalformedObject _ -> "object_malformed"
        IncompleteHistory _ -> "history_incomplete"
        ObjectReadFailure _ -> "object_read_failed"
