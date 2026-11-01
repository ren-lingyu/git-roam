{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Discard (previewDiscard, executeDiscard, DiscardPreview (..), DiscardResult (..), DiscardFailure (..)) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Inspect (inspectState, reportManagedState, validateCandidate)
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import GitRoam.Application.Worktree (RemovalPlan, checkRemovedWorktreePaths, planDiscardRemoval, removalTargets, removePlannedWorktree, restoreRemovedWorktree, withProtectedSession)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment, resolveCommitReference)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId (ObjectId, objectIdBytes)
import GitRoam.Protocol.Discard
import GitRoam.Protocol.Identity (NodeId, nodeIdBytes, parseNodeId)
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Exit (ExitCode (..))

-- A read-only report, not a token authorizing future execution.
data DiscardPreview = DiscardPreview
    { previewImpact :: DiscardImpact
    , previewWorktrees :: [Worktree]
    , previewProblems :: [String]
    , previewPlanId :: Maybe BS.ByteString
    }
    deriving (Eq, Show)

-- Only collection from the shared validators can construct an execution plan.
data Plan = Plan ManagedState DiscardPreview [Worktree] (Maybe RemovalPlan)
data DiscardResult = DiscardResult
    { resultPlanId :: BS.ByteString
    , resultDiscarded :: Set.Set ObjectId
    , resultRefs :: Map.Map NodeId ObjectId
    , resultWorktrees :: [Worktree]
    }
    deriving (Eq, Show)
data DiscardFailure = DiscardFailure String [String] deriving (Eq, Show)

previewDiscard :: Git IO -> FilePath -> [String] -> IO (Either String DiscardPreview)
previewDiscard git directory references = do
    outcome <- try (collect git directory references)
    pure $ either (Left . show) (fmap (\(Plan _ report _ _) -> report)) (outcome :: Either IOException (Either String Plan))

collect :: Git IO -> FilePath -> [String] -> IO (Either String Plan)
collect git directory references = runExceptT action
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
        safety <- lift (planDiscardRemoval git directory state affected)
        let safetyProblems = case safety of
                Left problem -> [problem]
                Right _ -> []
        -- Ref/worktree observations are rechecked, without taking an operation
        -- lock or writing optional index refreshes. This is not an atomic snapshot.
        bytes <- query ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"]
        let expected = Map.fromList [("refs/heads/" <> nodeIdBytes node, objectIdBytes oid) | (node, oid) <- Map.toList (managedRefs state)]
        pairs <- mapM decodeRef (BSC.lines bytes)
        unless (Map.fromList [pair | Just pair <- pairs] == expected) (throwE "Managed refs changed during discard preview")
        refreshed <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
        unless (records == refreshed) (throwE "Worktree registration changed during discard preview")
        let problems = representation ++ safetyProblems
            identifier = if null problems then Just (planId repository state impact records) else Nothing
        pure (Plan state (DiscardPreview impact relevant problems identifier) records (either (const Nothing) Just safety))
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

-- Versioned, unambiguous Show encodings bind repository, refs, exact impact
-- and actual registrations. Worktree cleanliness/metadata are rechecked, not
-- inferred from a digest. No permanent plan file or transaction log is created.
planId :: Repository -> ManagedState -> DiscardImpact -> [Worktree] -> BS.ByteString
planId repository state impact records = BS.concatMap hex (SHA256.hash payload)
  where
    payload =
        "git-roam-discard-v1\0"
            <> repositoryCommonDirectory repository
            <> "\0"
            <> BSC.pack (show (Map.toList (managedRefs state), Set.toList (discardTargets impact), Set.toList (discardVersions impact), discardReasons impact, discardNodes impact, sortOn treePath records))
    hex byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48 + n else 87 + n

loadState :: Git IO -> FilePath -> IO (Either String ManagedState)
loadState git directory = do
    result <- inspectState git directory [] Nothing
    pure $ case result of
        Left problem -> Left (show problem)
        Right report -> either (Left . show) Right (reportManagedState report)

command :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
command git directory args input = do
    outcome <- runGit git (GitInvocation directory args input readOnlyEnvironment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

executeDiscard :: FilePath -> Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either DiscardFailure DiscardResult)
executeDiscard executable git directory references authorization = do
    confirmed <- newIORef False
    attempted <- newIORef False
    removed <- newIORef []
    context <- newIORef Nothing
    outcome <- try $ withProtectedSession executable git directory $ \session -> do
        setup <- runExceptT $ do
            repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory readOnlyEnvironment))
            common <- lift (decodePath (repositoryCommonDirectory repository))
            lift (writeIORef context (Just (common, repositoryObjectFormat repository)))
            plan@(Plan _ report _ _) <- ExceptT (collect git common references)
            unless (null (previewProblems report)) (throwE (unlines (previewProblems report)))
            unless (previewPlanId report == Just authorization) (throwE "Discard plan changed or confirmation does not match; run --dry-run and review the complete impact again")
            pure (repository, common, plan)
        case setup of
            Left problem -> pure (Right (Left (DiscardFailure problem [])))
            Right (repository, common, Plan before report original (Just removal)) -> case discardCandidate (previewImpact report) of
                Nothing -> pure (Right (Left (DiscardFailure "No representable discard candidate" [])))
                Just after -> do
                    let affected = Set.fromList (map discardNode (discardNodes (previewImpact report)))
                        ordered = removalTargets removal
                        refs = managedRefs before
                        targetRefs = managedRefs after
                        verify state = do
                            actual <- ExceptT (loadState git common)
                            unless (managedRefs actual == managedRefs state && retainedCheckpoints actual == retainedCheckpoints state) (throwE "Managed state changed during discard")
                        restore records state = forM_ records $ \record -> ExceptT (restoreRemovedWorktree session state record)
                        expectedFinal = sortOn treePath [if maybe False (`Set.member` affected) (worktreeNode r) then r{treeHead = worktreeNode r >>= (`Map.lookup` targetRefs)} else r | r <- original]
                        apply = do
                            -- A final full safety/identity check precedes any removal.
                            Plan _ checked _ _ <- ExceptT (collect git common references)
                            unless (previewPlanId checked == Just authorization) (throwE "Discard plan became stale before execution")
                            forM_ ordered $ \record -> do
                                _ <- ExceptT (planDiscardRemoval git common before affected)
                                node <- maybe (throwE "Invalid removal target") pure (worktreeNode record)
                                ExceptT (removePlannedWorktree session removal node)
                                lift (modifyIORef' removed (++ [record]))
                            verify before
                            records <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
                            done <- lift (readIORef removed)
                            unless (sortOn treePath records == sortOn treePath (filter (\r -> treePath r `notElem` map treePath done) original)) (throwE "Worktree registrations changed before the ref transaction")
                            ExceptT (checkRemovedWorktreePaths session done)
                            ExceptT (requireProtectionFor executable common)
                            let ref node = "refs/heads/" <> nodeIdBytes node
                                updates = [if Set.member node affected then "update " <> ref node <> " " <> objectIdBytes (targetRefs Map.! node) <> " " <> objectIdBytes old else "verify " <> ref node <> " " <> objectIdBytes old | (node, old) <- Map.toList refs]
                            lift (writeIORef attempted True)
                            _ <- ExceptT (command git common (ownHookBypass ++ ["update-ref", "--stdin"]) (BSC.unlines (["start"] ++ updates ++ ["prepare", "commit"])))
                            lift (writeIORef confirmed True)
                            verify after
                            restore ordered after
                            verify after
                            final <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
                            unless (sortOn treePath final == expectedFinal) (throwE "Worktree restoration is incomplete or registrations changed")
                            ExceptT (requireProtectionFor executable common)
                            pure (DiscardResult authorization (discardVersions (previewImpact report)) targetRefs (filter (maybe False (`Set.member` affected) . worktreeNode) final))
                    applied <- try (runExceptT apply) :: IO (Either IOException (Either String DiscardResult))
                    case either (Left . show) id applied of
                        Right result -> pure (Right (Right result))
                        Left problem -> do
                            actual <- loadState git common
                            done <- readIORef removed
                            -- Restore deployment only, at the actual verified old or
                            -- candidate state. Never roll back a committed discard.
                            recovery <- case actual of
                                Right state | managedRefs state == refs || managedRefs state == targetRefs -> runExceptT $ do
                                    records <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
                                    restore [r | r <- done, all ((/= treePath r) . treePath) records] state
                                _ -> pure (Left "Refs are neither the verified original nor candidate state; no automatic restoration")
                            wasConfirmed <- readIORef confirmed
                            wasAttempted <- readIORef attempted
                            records <- listWorktrees git common (repositoryObjectFormat repository)
                            rawRefs <- command git common ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"] ""
                            let details =
                                    [ "Plan ID: " ++ BSC.unpack authorization
                                    , "Ref transaction attempted: " ++ show wasAttempted ++ "; confirmed: " ++ show wasConfirmed
                                    , "Actual refs: " ++ either id BSC.unpack rawRefs
                                    , "Actual managed-state validation: " ++ either id (show . managedRefs) actual
                                    , "Worktree restoration: " ++ either id (const "confirmed missing worktrees restored or already registered") recovery
                                    , "Actual worktrees: " ++ either id (show . map (\r -> (treePath r, treeBranch r, treeHead r))) records
                                    , "No formal-history rollback was attempted. Inspect actual state after failure."
                                    ]
                            pure (Right (Left (DiscardFailure problem details)))
            Right _ -> pure (Right (Left (DiscardFailure "Discard safety plan is unavailable" [])))
    case outcome of
        Left problem -> do
            wasConfirmed <- readIORef confirmed
            wasAttempted <- readIORef attempted
            known <- readIORef context
            details <- case known of
                Nothing -> pure []
                Just (common, format) -> do
                    raw <- command git common ["for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"] ""
                    records <- listWorktrees git common format
                    pure ["Actual refs: " ++ either id BSC.unpack raw, "Actual worktrees: " ++ either id (show . map (\r -> (treePath r, treeBranch r, treeHead r))) records]
            pure (Left (DiscardFailure (show (problem :: IOException)) (["Ref transaction attempted: " ++ show wasAttempted ++ "; confirmed: " ++ show wasConfirmed, "Operation interrupted; inspect actual state. No formal-history rollback was attempted."] ++ details)))
        Right (Left problem) -> pure (Left (DiscardFailure problem []))
        Right (Right result) -> pure result
