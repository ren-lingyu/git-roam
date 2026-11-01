{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Discard (previewDiscard, DiscardPreview (..)) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Inspect (inspectState, reportManagedState, validateCandidate)
import GitRoam.Application.Worktree (planRemovalFor, retainedMainWorktrees)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment, resolveCommitReference)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId (objectIdBytes)
import GitRoam.Protocol.Discard
import GitRoam.Protocol.Identity (nodeIdBytes, parseNodeId)
import GitRoam.Protocol.Repository
import GitRoam.Repository
import System.Exit (ExitCode (..))

-- A read-only report, not a token authorizing future execution.
data DiscardPreview = DiscardPreview
    { previewImpact :: DiscardImpact
    , previewWorktrees :: [Worktree]
    , previewProblems :: [String]
    }
    deriving (Eq, Show)

previewDiscard :: Git IO -> FilePath -> [String] -> IO (Either String DiscardPreview)
previewDiscard git directory references = do
    outcome <- try (runExceptT action)
    pure $ either (Left . show) id (outcome :: Either IOException (Either String DiscardPreview))
  where
    action = do
        unless (not (null references)) (throwE "Specify at least one explicit Checkpoint ref or OID")
        found <- lift (inspectRepository git directory readOnlyEnvironment)
        repository <- either (throwE . show) pure found
        observed <- lift (inspectState git directory [] Nothing)
        report <- either (throwE . show) pure observed
        state <- either (throwE . show) pure (reportManagedState report)
        targets <- Set.fromList <$> mapM (ExceptT . resolveCommitReference git directory (repositoryObjectFormat repository) []) references
        impact <- either throwE pure (computeDiscard state targets)
        -- Validate the entire candidate, including payload completeness. An
        -- unrepresentable result still produces the full formal impact report.
        case discardCandidate impact of
            Nothing -> pure ()
            Just target -> do
                actual <- lift (validateCandidate git directory (managedRefs target))
                checked <- either (throwE . show) pure actual
                unless (retainedCheckpoints checked == retainedCheckpoints target) (throwE "Candidate formal history changed during preview")
        records <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
        let affected = Set.fromList (map discardNode (discardNodes impact))
            relevant = filter (maybe False (`Set.member` affected) . worktreeNode) records
            representation = ["Remaining history has multiple maximal Checkpoints for Node " ++ BSC.unpack (nodeIdBytes (discardNode n)) ++ ": " ++ unwords (map (BSC.unpack . objectIdBytes) (Set.toList (discardRemainingMaxima n))) | n <- discardNodes impact, discardNewTip n == Nothing]
        safety <- lift (planRemovalFor git directory state affected)
        let safetyProblems = case safety of
                Left problem -> [problem]
                Right plan -> ["Affected Node is checked out in the main worktree; safe discard execution is not available for it: " ++ show (treePath record) | record <- retainedMainWorktrees plan]
        -- Ref/worktree observations are rechecked, without taking an operation
        -- lock or writing optional index refreshes. This is not an atomic snapshot.
        bytes <- query ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"]
        let expected = Map.fromList [("refs/heads/" <> nodeIdBytes node, objectIdBytes oid) | (node, oid) <- Map.toList (managedRefs state)]
        pairs <- mapM decodeRef (BSC.lines bytes)
        unless (Map.fromList [pair | Just pair <- pairs] == expected) (throwE "Managed refs changed during discard preview")
        refreshed <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
        unless (records == refreshed) (throwE "Worktree registration changed during discard preview")
        pure (DiscardPreview impact relevant (representation ++ safetyProblems))
    query arguments = do
        outcome <- lift (runGit git (GitInvocation directory arguments BS.empty readOnlyEnvironment))
        case outcome of
            Left problem -> throwE (show problem)
            Right result | gitExitCode result == ExitSuccess && BS.null (gitStderr result) -> pure (gitStdout result)
            Right result -> throwE (show arguments ++ ": " ++ show (gitStderr result))
    decodeRef row = case BS.split 0 row of
        [ref, oid, symbolic] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> pure Nothing
            Just _ | BS.null symbolic -> pure (Just (ref, oid))
            _ -> throwE "Symbolic Node ref encountered during preview"
        _ -> throwE "Invalid managed reference observation"
