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
import qualified GitRoam.Application.Inspect as Inspection
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

-- A preview never authorizes mutation. executeDelete rebuilds its private
-- Plan under the operation lock and compares the complete confirmation token.
data DeletePreview = DeletePreview
    { deleteNode :: NodeId
    , deleteOldTip :: ObjectId
    , deleteRoot :: ObjectId
    , deleteExclusiveCommits :: Set.Set ObjectId
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
    result <- Inspection.inspectState git directory [] Nothing
    pure $ either (Left . show) (either (Left . show) Right . Inspection.reportManagedState) result

collect :: Git IO -> FilePath -> NodeId -> IO (Either String Plan)
collect git directory node = runExceptT $ do
    repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory readOnlyEnvironment))
    before <- ExceptT (loadState git directory)
    old <- maybe (throwE "The explicit UUID has no managed local Node branch") pure (Map.lookup node (managedRefs before))
    let history = managedHistory before
        candidateRefs = Map.delete node (managedRefs before)
    tip <- maybe (throwE "Validated Node tip is missing") pure (lookupCommit history old)
    -- Unlike v0.1.0, a context reference does not prevent removing this
    -- branch. Git keeps all objects still reachable through the other tips.
    target <- ExceptT (fmap (either (Left . show) Right) (Inspection.validateCandidate git directory candidateRefs))
    fromTarget <- either (throwE . show) pure (reachableHistory history old)
    fromOthers <-
        either
            (throwE . show)
            pure
            (reachableHistoryFrom history (Map.elems candidateRefs))
    let exclusive = fromTarget `Set.difference` fromOthers
    records <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    config <- ExceptT (localConfig git directory node)
    let checkouts = filter ((== Just node) . worktreeNode) records
        problems = ["Target Node branch is checked out; safely handle its worktrees before deletion" | not (null checkouts)]
        payload = "git-roam-node-delete-v2\0" <> repositoryCommonDirectory repository <> "\0" <> BSC.pack (show (Map.toList (managedRefs before), node, old, exclusive, sortOn treePath records, config))
        identifier = BS.concatMap hex (SHA256.hash payload)
        report = DeletePreview node old (validatedRoot tip) exclusive checkouts (map fst config) problems (if null problems then Just identifier else Nothing)
    observed <- ExceptT (loadState git directory)
    unless (managedRefs observed == managedRefs before) (throwE "Managed refs changed during deletion preview")
    refreshed <- ExceptT (listWorktrees git directory (repositoryObjectFormat repository))
    configNow <- ExceptT (localConfig git directory node)
    unless (records == refreshed && configNow == config) (throwE "Worktree or branch configuration changed during preview")
    pure (Plan before target report records config repository)
  where
    hex byte = BS.pack [digit (byte `div` 16), digit (byte `mod` 16)]
    digit n = if n < 10 then 48 + n else 87 + n

previewDelete :: Git IO -> FilePath -> NodeId -> IO (Either String DeletePreview)
previewDelete git directory node = do
    outcome <- try (collect git directory node)
    pure $ either (Left . show) (fmap (\(Plan _ _ report _ _ _) -> report)) (outcome :: Either IOException (Either String Plan))

executeDelete :: FilePath -> Git IO -> FilePath -> NodeId -> BS.ByteString -> IO (Either DeleteFailure DeletePreview)
executeDelete executable git directory node authorization = do
    attempted <- newIORef False
    confirmed <- newIORef False
    outcome <- try $ withProtectedSession executable git directory $ \_ -> runExceptT $ do
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
        unless (managedRefs actual == managedRefs after) (throwE "Actual managed refs differ after Node deletion")
        current <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
        unless (sortOn treePath current == sortOn treePath original) (throwE "Worktree registrations changed during Node deletion")
        observedConfig <- ExceptT (localConfig git common node)
        unless (observedConfig == config) (throwE "Branch configuration changed; ref deleted but configuration was left untouched")
        -- Never clear a whole section or included/global settings. Remove only
        -- the exact values reviewed in the confirmation plan.
        forM_ (Set.toList (Set.fromList config)) $ \(key, value) -> do
            name <- lift (decodePath key)
            literal <- lift (decodePath value)
            _ <- ExceptT (query git common ["config", "--local", "--no-includes", "--fixed-value", "--unset-all", name, literal] "")
            pure ()
        residual <- ExceptT (localConfig git common node)
        unless (null residual) (throwE "Local branch configuration cleanup is incomplete")
        final <- ExceptT (loadState git common)
        unless (managedRefs final == managedRefs after) (throwE "Managed refs changed after configuration cleanup")
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
