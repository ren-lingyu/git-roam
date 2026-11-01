{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Delete (DeletePreview (..), DeleteFailure (..), previewDelete, executeDelete) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Inspect (inspectState, reportManagedState, validateCandidate)
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import GitRoam.Application.Worktree (withProtectedSession)
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Exit (ExitCode (..))

-- Diagnostic data cannot authorize an update; the private Plan is rebuilt.
data DeletePreview = DeletePreview
    { deleteNode :: NodeId
    , deleteOldTip :: ObjectId
    , deleteRoot :: ObjectId
    , deleteVersions :: Set.Set ObjectId
    , deleteContent :: Set.Set ObjectId
    , deleteIncoming :: [(NodeId, ObjectId, ObjectId)]
    , deleteWorktrees :: [Worktree]
    , deleteConfigKeys :: [BS.ByteString]
    , deleteProblems :: [String]
    , deletePlanId :: Maybe BS.ByteString
    }
    deriving (Eq, Show)

data DeleteFailure = DeleteFailure String [String] deriving (Eq, Show)
data Plan = Plan ManagedState ManagedState DeletePreview [Worktree] [(BS.ByteString, BS.ByteString)] Repository

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    result <- runGit git (GitInvocation directory args input readOnlyEnvironment)
    pure $ case result of
        Left problem -> Left (show problem)
        Right value | gitExitCode value == ExitSuccess -> Right (gitStdout value)
        Right value -> Left ("Git operation failed: " ++ show (gitExitCode value))

localConfig :: Git IO -> FilePath -> NodeId -> IO (Either String [(BS.ByteString, BS.ByteString)])
localConfig git directory node = do
    result <- runGit git (GitInvocation directory ["config", "--local", "--no-includes", "--null", "--get-regexp", "^branch\\." ++ BSC.unpack (nodeIdBytes node) ++ "\\."] "" readOnlyEnvironment)
    pure $ case result of
        Right value | gitExitCode value == ExitFailure 1 && BS.null (gitStdout value) && BS.null (gitStderr value) -> Right []
        Right value | gitExitCode value == ExitSuccess -> do
            let bytes = gitStdout value
            unless (BS.null bytes || BS.last bytes == 0) (Left "Truncated local branch configuration")
            mapM entry (if BS.null bytes then [] else BS.split 0 (BS.init bytes))
        _ -> Left "Cannot read local branch configuration"
  where
    entry bytes = case BSC.break (== '\n') bytes of
        (key, value) | not (BS.null value) -> Right (key, BS.tail value)
        _ -> Left "Valueless local Node branch configuration requires manual handling before deletion"

loadState :: Git IO -> FilePath -> IO (Either String ManagedState)
loadState git directory = do
    result <- inspectState git directory [] Nothing
    pure $ either (Left . show) (either (Left . show) Right . reportManagedState) result

collect :: Git IO -> FilePath -> NodeId -> IO (Either String Plan)
collect git directory node = runExceptT $ do
    repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory readOnlyEnvironment))
    before <- ExceptT (loadState git directory)
    old <- maybe (throwE "The explicit UUID has no managed local Node branch") pure (Map.lookup node (managedRefs before))
    value <- maybe (throwE "Validated Node tip is missing") pure (lookupCommit (managedHistory before) old)
    let history = managedHistory before
        versions = Map.findWithDefault Set.empty node (retainedCheckpoints before)
    incoming <- fmap concat $ mapM (edges history) [(other, oid) | (other, oids) <- Map.toList (retainedCheckpoints before), other /= node, oid <- Set.toList oids]
    let candidateRefs = Map.delete node (managedRefs before)
        -- A blocked preview still reports all incoming edges and checkouts.
        target = validateManagedState history candidateRefs
    after <- if null incoming then either (throwE . show) pure target else pure before
    unless (not (null incoming) || retainedCheckpoints after == Map.delete node (retainedCheckpoints before)) (throwE "Deletion would alter another Node's formal history")
    whenValid incoming $ do
        checked <- ExceptT (fmap (either (Left . show) Right) (validateCandidate git directory candidateRefs))
        unless (retainedCheckpoints checked == retainedCheckpoints after) (throwE "Candidate changed during validation")
    records <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    config <- ExceptT (localConfig git directory node)
    contents <- either throwE pure (contentHistory history [old])
    remaining <- either throwE pure (contentHistory history (Map.elems candidateRefs))
    let checkouts = filter ((== Just node) . worktreeNode) records
        problems = ["Other retained Node history depends on the target; discard that history explicitly first" | not (null incoming)] ++ ["Target Node branch is checked out; safely handle its worktrees before deletion" | not (null checkouts)]
        payload = "git-roam-node-delete-v1\0" <> repositoryCommonDirectory repository <> "\0" <> BSC.pack (show (Map.toList (managedRefs before), node, versions, contents `Set.difference` remaining, incoming, sortOn treePath records, config))
        identifier = BS.concatMap hex (SHA256.hash payload)
        report = DeletePreview node old (validatedRoot value) versions (contents `Set.difference` remaining) incoming checkouts (map fst config) problems (if null problems then Just identifier else Nothing)
    observed <- ExceptT (loadState git directory)
    unless (managedRefs observed == managedRefs before && retainedCheckpoints observed == retainedCheckpoints before) (throwE "Managed state changed during deletion preview")
    refreshed <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    configNow <- ExceptT (localConfig git directory node)
    unless (records == refreshed && configNow == config) (throwE "Worktree or branch configuration changed during preview")
    pure (Plan before after report records config repository)
  where
    whenValid incoming action = if null incoming then action else pure ()
    edges history (other, oid) = case projectCheckpoint history oid of
        Right (Just version) -> pure [(other, oid, required) | Just required <- [Map.lookup node (versionDependencies version)]]
        _ -> throwE "Retained Checkpoint is missing"
    hex byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48 + n else 87 + n

contentHistory :: ValidatedHistory -> [ObjectId] -> Either String (Set.Set ObjectId)
contentHistory history = walk Set.empty Set.empty
  where
    walk _ contents [] = Right contents
    walk seen contents (oid : rest)
        | Set.member oid seen = walk seen contents rest
        | otherwise = case lookupCommit history oid of
            Nothing -> Left "Reachable object is missing from validated history"
            Just value -> case validatedKind value of
                Root -> walk next contents rest
                Content parent _ -> walk next (Set.insert oid contents) (parent : rest)
                Checkpoint parents -> walk next contents (mainPredecessor parents : contentTip parents : Set.toList (mergedPredecessors parents) ++ Map.elems (directDependencies parents) ++ rest)
      where
        next = Set.insert oid seen

previewDelete :: Git IO -> FilePath -> NodeId -> IO (Either String DeletePreview)
previewDelete git directory node = do
    outcome <- try (collect git directory node)
    pure $ either (Left . show) (fmap (\(Plan _ _ report _ _ _) -> report)) (outcome :: Either IOException (Either String Plan))

executeDelete :: FilePath -> Git IO -> FilePath -> NodeId -> BS.ByteString -> IO (Either DeleteFailure DeletePreview)
executeDelete executable git directory node authorization = do
    attempted <- newIORef False
    confirmed <- newIORef False
    outcome <- try $ withProtectedSession executable git directory $ \_ -> runExceptT $ do
        -- Resolve the common directory before any mutation, including invocation
        -- from a detached worktree. Never move, clean or remove worktrees here.
        Plan _ _ _ _ _ repository <- ExceptT (collect git directory node)
        common <- lift (decodePath (repositoryCommonDirectory repository))
        Plan before after report original config _ <- ExceptT (collect git common node)
        unless (null (deleteProblems report)) (throwE (unlines (deleteProblems report)))
        unless (deletePlanId report == Just authorization) (throwE "Deletion plan changed or confirmation does not match; review --dry-run again")
        ExceptT (requireProtectionFor executable common)
        let ref n = "refs/heads/" <> nodeIdBytes n
            changes = [if n == node then "delete " <> ref n <> " " <> objectIdBytes old else "verify " <> ref n <> " " <> objectIdBytes old | (n, old) <- Map.toList (managedRefs before)]
        lift (writeIORef attempted True)
        _ <- ExceptT (query git common (ownHookBypass ++ ["update-ref", "--stdin"]) (BSC.unlines (["start"] ++ changes ++ ["prepare", "commit"])))
        lift (writeIORef confirmed True)
        actual <- ExceptT (loadState git common)
        unless (managedRefs actual == managedRefs after && retainedCheckpoints actual == retainedCheckpoints after) (throwE "Actual managed state differs after Node deletion")
        current <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
        unless (sortOn treePath current == sortOn treePath original) (throwE "Worktree registrations changed during Node deletion")
        observedConfig <- ExceptT (localConfig git common node)
        unless (observedConfig == config) (throwE "Branch configuration changed; ref deleted but configuration was left untouched")
        -- Only remove exact reviewed local values, never a whole section or
        -- included/global configuration. Partial cleanup is reported as failure.
        forM_ (Set.toList (Set.fromList config)) $ \(key, value) -> do
            name <- lift (decodePath key)
            literal <- lift (decodePath value)
            _ <- ExceptT (query git common ["config", "--local", "--no-includes", "--fixed-value", "--unset-all", name, literal] "")
            pure ()
        residual <- ExceptT (localConfig git common node)
        unless (null residual) (throwE "Local branch configuration cleanup is incomplete")
        final <- ExceptT (loadState git common)
        unless (managedRefs final == managedRefs after && retainedCheckpoints final == retainedCheckpoints after) (throwE "Managed state changed after configuration cleanup")
        finalWorktrees <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
        unless (sortOn treePath finalWorktrees == sortOn treePath original) (throwE "Worktree registrations changed after configuration cleanup")
        ExceptT (requireProtectionFor executable common)
        pure report
    case (outcome :: Either IOException (Either String DeletePreview)) of
        Right (Right report) -> pure (Right report)
        other -> do
            tried <- readIORef attempted
            done <- readIORef confirmed
            actual <- try (loadState git directory) :: IO (Either IOException (Either String ManagedState))
            configuration <- try (localConfig git directory node) :: IO (Either IOException (Either String [(BS.ByteString, BS.ByteString)]))
            let reason = either show (either id (const "Deletion failed")) other
                refs = case actual of
                    Right (Right state) -> ("actual target branch present: " ++ show (Map.member node (managedRefs state))) : ["actual node " ++ BSC.unpack (nodeIdBytes n) ++ " " ++ BSC.unpack (objectIdBytes oid) | (n, oid) <- Map.toList (managedRefs state)]
                    _ -> ["Actual managed state could not be fully validated; run git roam check"]
                configDetails = case configuration of
                    Right (Right entries) -> ("Remaining reviewed-scope local config entries: " ++ show (length entries)) : ["remaining local config key " ++ BSC.unpack key | (key, _) <- entries]
                    _ -> ["Local branch configuration could not be fully inspected"]
            pure (Left (DeleteFailure reason (["Deletion transaction attempted: " ++ show tried ++ "; response confirmed: " ++ show done, "No automatic ref rollback or worktree cleanup was performed."] ++ refs ++ configDetails)))
