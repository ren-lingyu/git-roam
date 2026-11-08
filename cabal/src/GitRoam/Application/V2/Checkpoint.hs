{-# LANGUAGE OverloadedStrings #-}

-- Native Checkpoint constructor for the proposed context protocol.
-- The public CLI continues to use Application.Checkpoint until cutover.
module GitRoam.Application.V2.Checkpoint (
    CheckpointResult (..),
    CheckpointFailure (..),
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
import GitRoam.Application.Protection (ownHookBypass, requireProtectionFor)
import qualified GitRoam.Application.V2.Inspect as Inspection
import GitRoam.Application.Worktree (withProtectedSession)
import GitRoam.Git
import GitRoam.Git.Objects (checkStoredConnectivity, readOnlyEnvironment, resolveCommitReference, withHistorySource)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.V2.History
import GitRoam.Protocol.V2.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)
import System.Exit (ExitCode (..))

data CheckpointResult = CheckpointResult
    { checkpointNode :: NodeId
    , checkpointOid :: ObjectId
    , checkpointPredecessor :: ObjectId
    , checkpointContexts :: [ObjectId]
    }
    deriving (Eq, Show)

data CheckpointFailure = CheckpointFailure String [String] deriving (Eq, Show)

-- Selection is ordered and explicit. Unlike v0.1.0 no inherited context is
-- consulted, and no synthetic Content object is made. Node inference and
-- command-line syntax belong to the later atomic application cutover.
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
prepare :: Git IO -> FilePath -> ObjectFormat -> ManagedState -> NodeId -> [String] -> IO (Either String (ObjectId, ObjectId, [ObjectId]))
prepare git directory format before node revisions = runExceptT $ do
    when (null revisions) (throwE "A Checkpoint requires at least one external context")
    old <- maybe (throwE "No managed branch for the selected Node") pure (Map.lookup node (managedRefs before))
    tip <- maybe (throwE "Validated Node tip is unavailable") pure (lookupCommit (managedHistory before) old)
    contexts <- forM revisions (ExceptT . resolveCommitReference git directory format environment)
    when (length contexts /= Set.size (Set.fromList contexts)) (throwE "Duplicate context commit OID")
    checked <- lift $ withHistorySource git directory format environment $ \source -> runExceptT $ do
        loaded <- lift (validateHistory format source (Map.elems (managedRefs before) ++ contexts))
        history <- either (throwE . show) pure loaded
        forM_ contexts $ \oid -> do
            value <- maybe (throwE "Selected context is missing from validated history") pure (lookupCommit history oid)
            when (validatedNode value == node) (throwE "Checkpoint context must belong to another Node")
        evidence <- lift (checkStoredConnectivity git directory environment source contexts)
        missing <- either (throwE . show) pure evidence
        unless (null missing) (throwE ("Selected context has missing Git objects: " ++ show missing))
    either (throwE . show) (either throwE pure) checked
    pure (old, validatedTree tip, contexts)

-- The protected operation lock serializes Git-roam writers, but native Git
-- competitors may still race: verify every other managed ref and use an
-- expected-old update for this Node. The old protocol Hook is bypassed only
-- for this validated candidate; all other named Hooks remain active.
checkpoint :: FilePath -> Git IO -> FilePath -> NodeId -> BS.ByteString -> [String] -> IO (Either CheckpointFailure CheckpointResult)
checkpoint executable git directory node message revisions = do
    candidate <- newIORef Nothing
    installed <- newIORef False
    outcome <- try $ withProtectedSession executable git directory $ \_ -> runExceptT $ do
        either throwE pure (messageValid message)
        repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory environment))
        common <- lift (decodePath (repositoryCommonDirectory repository))
        before <- ExceptT (stateAt git common)
        (old, tree, contexts) <- ExceptT (prepare git common (repositoryObjectFormat repository) before node revisions)
        forM_ ["GIT_AUTHOR_IDENT", "GIT_COMMITTER_IDENT"] $ \ident -> do
            _ <- ExceptT (query git common ["var", ident] "")
            pure ()
        let args =
                ["-c", "i18n.commitEncoding=UTF-8", "commit-tree", BSC.unpack (objectIdBytes tree)]
                    ++ concatMap (\oid -> ["-p", BSC.unpack (objectIdBytes oid)]) (old : contexts)
                    ++ ["-F", "-"]
        bytes <- ExceptT (query git common args message)
        oid <- either throwE pure (maybe (Left "Invalid commit-tree response") (parseObjectId (repositoryObjectFormat repository)) (BS.stripSuffix "\n" bytes))
        let result = CheckpointResult node oid old contexts
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
            pure (Left (CheckpointFailure reason details))
