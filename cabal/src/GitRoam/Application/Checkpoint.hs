{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

module GitRoam.Application.Checkpoint (
    CheckpointResult (..),
    CheckpointFailure (CheckpointFailure),
    checkpointFailureEvidence,
    checkpointFailureDiagnostic,
    checkpoint,
) where

import Control.Exception (IOException, try)
import Control.Monad (forM, forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Inspect as Inspection
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import GitRoam.Application.Worktree (withProtectedSession)
import GitRoam.Diagnostic (Diagnostic (..), Evidence (..), Severity (..), emptyEvidence)
import GitRoam.Git
import GitRoam.Git.Objects (checkStoredConnectivity, readOnlyEnvironment, resolveCommitReference, withHistorySource)
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Exit (ExitCode (..))

data CheckpointResult = CheckpointResult
    { checkpointNode :: NodeId
    , checkpointOid :: ObjectId
    , checkpointPredecessor :: ObjectId
    , checkpointContexts :: [ObjectId]
    , checkpointWarnings :: [String]
    }
    deriving (Eq, Show)

data CheckpointFailure = CheckpointFailureData String [String] (Maybe Evidence) Diagnostic deriving (Eq, Show)

pattern CheckpointFailure :: String -> [String] -> CheckpointFailure
pattern CheckpointFailure reason details <- CheckpointFailureData reason details _ _
    where
        CheckpointFailure reason details = CheckpointFailureData reason details Nothing (Diagnostic "checkpoint_failed" Error (Text.pack reason))
{-# COMPLETE CheckpointFailure #-}

checkpointFailureEvidence :: CheckpointFailure -> Maybe Evidence
checkpointFailureEvidence (CheckpointFailureData _ _ evidence _) = evidence

checkpointFailureDiagnostic :: CheckpointFailure -> Diagnostic
checkpointFailureDiagnostic (CheckpointFailureData _ _ _ value) = value

withEvidence :: Evidence -> CheckpointFailure -> CheckpointFailure
withEvidence evidence (CheckpointFailureData reason details _ diagnosticValue) = CheckpointFailureData reason details (Just evidence) diagnosticValue

-- Selection is ordered and explicit. No inherited context is consulted and
-- no synthetic Content object is made. An omitted Node is inferred when the
-- current worktree's symbolic HEAD names a canonical local Node branch.
environment :: [(String, Maybe String)]
environment = readOnlyEnvironment ++ [(name, Nothing) | name <- ["GIT_DIR", "GIT_COMMON_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"]]

query :: Git IO -> FilePath -> [String] -> BS.ByteString -> IO (Either String BS.ByteString)
query git directory args input = do
    outcome <- runGit git (GitInvocation directory args input environment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result | gitExitCode result == ExitSuccess && ("rev-parse" `notElem` args || BS.null (gitStderr result)) -> Right (gitStdout result)
        Right result -> Left (show args ++ ": " ++ show (gitStderr result))

stateAt :: Git IO -> FilePath -> IO (Either String ManagedState)
stateAt git directory = do
    outcome <- Inspection.inspectState git directory [] Nothing
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right report -> either (Left . show) Right (Inspection.reportManagedState report)

messageValid :: BS.ByteString -> Either String ()
messageValid bytes = do
    text <- either (const (Left "Checkpoint message must be UTF-8")) Right (Encoding.decodeUtf8' bytes)
    unless (not (Text.null (Text.strip text)) && not (BS.elem 0 bytes)) (Left "Checkpoint message must be nonempty text without NUL bytes")

-- Explicit context revisions may name any valid stored commit, even one no
-- longer retained by its own Node branch. Validate all chosen objects before
-- writing a candidate, including their blob/tree connectivity.
prepare :: Git IO -> FilePath -> ObjectFormat -> ManagedState -> NodeId -> [String] -> IO (Either String (ObjectId, ObjectId, [ObjectId], [String]))
prepare git directory format before node revisions = runExceptT $ do
    when (null revisions) (throwE "A Checkpoint requires at least one external context")
    old <- maybe (throwE "No managed branch for the selected Node") pure (Map.lookup node (managedRefs before))
    tip <- maybe (throwE "Validated Node tip is unavailable") pure (lookupCommit (managedHistory before) old)
    contexts <- forM revisions (ExceptT . resolveCommitReference git directory format environment)
    when (length contexts /= Set.size (Set.fromList contexts)) (throwE "Duplicate context commit OID")
    checked <- lift $ withHistorySource git directory format environment $ \source -> runExceptT $ do
        loaded <- lift (validateHistory format source (Map.elems (managedRefs before) ++ contexts))
        history <- either (throwE . show) pure loaded
        contextNodes <- forM contexts $ \oid -> do
            value <- maybe (throwE "Selected context is missing from validated history") pure (lookupCommit history oid)
            when (validatedNode value == node) (throwE "Checkpoint context must belong to another Node")
            pure (validatedNode value)
        evidence <- lift (checkStoredConnectivity git directory environment source contexts)
        missing <- either (throwE . show) pure evidence
        unless (null missing) (throwE ("Selected context has missing Git objects: " ++ show missing))
        let repeatedNode = length contextNodes /= Set.size (Set.fromList contextNodes)
            warnings =
                [ "Multiple context commits belong to the same Node; compatibility is guaranteed only when all parents belong to distinct Nodes."
                | repeatedNode
                ]
        pure warnings
    warnings <- either (throwE . show) (either throwE pure) checked
    pure (old, validatedTree tip, contexts, warnings)

-- The protected operation lock serializes Git-roam writers, but native Git
-- competitors may still race: verify every other managed ref and use an
-- expected-old update for this Node. The protocol Hook is bypassed only for
-- this validated candidate; all other named Hooks remain active.
checkpoint :: FilePath -> Git IO -> FilePath -> Maybe NodeId -> BS.ByteString -> [String] -> IO (Either CheckpointFailure CheckpointResult)
checkpoint executable git directory requested message revisions = do
    candidate <- newIORef Nothing
    installed <- newIORef False
    outcome <- try $ withProtectedSession executable git directory $ \_ -> runExceptT $ do
        either throwE pure (messageValid message)
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        node <- case requested of
            Just value -> pure value
            Nothing -> do
                inferred <- ExceptT (fmap (either (Left . show) Right) (Inspection.inferNode git directory))
                maybe (throwE "Select --node UUID or run inside a Node worktree") pure inferred
        before <- ExceptT (stateAt git common)
        (old, tree, contexts, warnings) <- ExceptT (prepare git common (repositoryObjectFormat repository) before node revisions)
        forM_ ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] $ \ident -> do
            _ <- ExceptT (query git common ["var", ident] "")
            pure ()
        let args =
                ["-c", "i18n.commitEncoding=UTF-8", "commit-tree", BSC.unpack (objectIdBytes tree)]
                    ++ concatMap (\oid -> ["-p", BSC.unpack (objectIdBytes oid)]) (old : contexts)
                    ++ ["-F", "-"]
        bytes <- ExceptT (query git common args message)
        oid <- either throwE pure (maybe (Left "Invalid commit-tree response") (parseObjectId (repositoryObjectFormat repository)) (BS.stripSuffix "\n" bytes))
        let result = CheckpointResult node oid old contexts warnings
        lift (writeIORef candidate (Just result))
        target <- ExceptT (fmap (either (Left . show) Right) (Inspection.validateCandidate git common (Map.insert node oid (managedRefs before))))
        either (throwE . show) pure (validateOrdinaryTransition before target)
        current <- ExceptT (stateAt git common)
        unless (managedRefs current == managedRefs before) (throwE "Node refs changed before Checkpoint installation")
        let ref n = "refs/heads/" <> nodeIdBytes n
            input =
                BSC.unlines
                    ( ["start"]
                        ++ ["verify " <> ref n <> " " <> objectIdBytes oldOid | (n, oldOid) <- Map.toList (managedRefs before), n /= node]
                        ++ ["update " <> ref node <> " " <> objectIdBytes oid <> " " <> objectIdBytes old, "prepare", "commit"]
                    )
        _ <- ExceptT (query git common (ownHookBypass ++ ["update-ref", "--stdin"]) input)
        lift (writeIORef installed True)
        actual <- ExceptT (stateAt git common)
        unless (managedRefs actual == managedRefs target) (throwE "Node refs changed after Checkpoint installation")
        ExceptT (requireProtectionFor executable common)
        pure result
    case (outcome :: Either IOException (Either String CheckpointResult)) of
        Right (Right result) -> pure (Right result)
        other -> do
            proposed <- readIORef candidate
            advanced <- readIORef installed
            let reason = case other of
                    Left problem -> show problem
                    Right (Left problem) -> problem
                details = case proposed of
                    Nothing -> []
                    Just value ->
                        [ "Node: " ++ show (checkpointNode value)
                        , "Candidate Checkpoint: " ++ show (checkpointOid value)
                        , if advanced
                            then "Ref update completed before follow-up failure; no history rollback was attempted."
                            else "Object construction does not prove ref installation; inspect actual refs. No history rollback was attempted."
                        ]
            pure $ Left $ case proposed of
                Nothing -> CheckpointFailure reason details
                Just value -> withEvidence (emptyEvidence{evidenceNode = Just (checkpointNode value), evidenceCandidate = Just (checkpointOid value), evidenceRefConfirmed = Just advanced}) (CheckpointFailure reason details)
