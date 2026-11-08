{-# LANGUAGE OverloadedStrings #-}

-- An isolated reference-transaction validator for the context protocol.
-- The public Hook entry point continues to use Application.Protection until
-- the application-layer cutover; this module does not install or bypass Hooks.
module GitRoam.Application.V2.Protection (evaluateTransaction) where

import Control.Monad (foldM, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.Application.Protection (withOperationLock)
import qualified GitRoam.Application.V2.Inspect as Inspection
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.V2.History (CommitKind (..), lookupCommit, validatedKind)
import GitRoam.Protocol.V2.Repository (ManagedState, managedHistory, validateOrdinaryTransition)
import GitRoam.Repository
import System.Exit (ExitCode (..))

native :: Git IO
native = nativeGit defaultGitExecutable

checked :: FilePath -> [String] -> IO (Either String BS.ByteString)
checked directory arguments = do
    outcome <- runGit native (GitInvocation directory ("--no-replace-objects" : arguments) BS.empty readOnlyEnvironment)
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right result
            | gitExitCode result == ExitSuccess
            , not ("for-each-ref" `elem` arguments && not (BS.null (gitStderr result))) ->
                Right (gitStdout result)
        Right result -> Left (show arguments ++ ": " ++ show (gitStderr result))

-- Prepared is the only phase where a native Git ref transaction may be
-- rejected. The supplied old OID is not authoritative (it can be all zeros);
-- read the actual local refs under the operation lock instead.
evaluateTransaction :: FilePath -> String -> BS.ByteString -> IO (Either String ())
evaluateTransaction _ phase _ | phase /= "prepared" = pure (Right ())
evaluateTransaction directory _ input = case traverse parseUpdate (BSC.lines input) of
    Left problem -> pure (Left problem)
    Right rows -> case [update | Just update <- rows] of
        [] -> pure (Right ())
        updates -> withOperationLock directory $ runExceptT $ do
            discovered <- lift (inspectRepository native directory readOnlyEnvironment)
            repository <- either (throwE . show) pure discovered
            let format = repositoryObjectFormat repository
                nodes = map fst updates
            when (length nodes /= Set.size (Set.fromList nodes)) (throwE "Duplicate Node branch updates in one transaction")
            raw <- ExceptT (checked directory ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"])
            before <- Map.fromList . concat <$> mapM (decodeRef format) (BSC.lines raw)
            after <- foldM (apply format before) before updates
            -- A direct Content extension or amendment adds no context edges.
            -- Only these cases can safely validate a single Node: any new
            -- Checkpoint or arbitrary rewrite must be checked against *all*
            -- managed refs, so two different Roots of an external Node cannot
            -- evade cross-branch conflict detection.
            local <- case updates of
                [(node, _)] -> do
                    let selected = \refs -> Map.restrictKeys refs (Set.singleton node)
                    oldState <- lift (Inspection.validateCandidate native directory (selected before)) >>= either (throwE . show) pure
                    newState <- lift (Inspection.validateCandidate native directory (selected after)) >>= either (throwE . show) pure
                    let oldTip = before Map.! node
                        newTip = after Map.! node
                        simpleContent = localContent oldTip newTip oldState newState
                    when simpleContent (either (throwE . show) pure (validateOrdinaryTransition oldState newState))
                    pure simpleContent
                _ -> pure False
            unless local $ do
                oldState <- lift (Inspection.validateCandidate native directory before) >>= either (throwE . show) pure
                newState <- lift (Inspection.validateCandidate native directory after) >>= either (throwE . show) pure
                either (throwE . show) pure (validateOrdinaryTransition oldState newState)
  where
    parseUpdate row = case BSC.words row of
        [_old, new, ref] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> Right Nothing
            Just node -> Right (Just (node, new))
        -- HEAD and other non-Node refs may coexist in the same transaction.
        _ -> Left "Malformed reference-transaction input"

    decodeRef format row = case BS.split 0 row of
        [ref, oid, symbolic] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> pure []
            Just node -> do
                unless (BS.null symbolic) (throwE "Symbolic Node branches cannot be updated")
                object <- either throwE pure (parseObjectId format oid)
                pure [(node, object)]
        _ -> throwE "Malformed managed reference observation"

    apply format before state (node, bytes) = do
        unless (Map.member node before) (throwE "New Node branches require a controlled Git-roam operation")
        when (BS.null bytes || BS.all (== 48) bytes) (throwE "Node deletion requires an explicit Git-roam operation")
        oid <- either throwE pure (parseObjectId format bytes)
        pure (Map.insert node oid state)

-- Never use the scoped fast path for newly introduced Checkpoints or more
-- general rewrites: they may introduce historical context from another Root.
localContent :: ObjectId -> ObjectId -> ManagedState -> ManagedState -> Bool
localContent oldTip newTip oldState newState =
    case (lookupCommit (managedHistory oldState) oldTip, lookupCommit (managedHistory newState) newTip) of
        (Just old, Just new) -> case validatedKind new of
            Content parent ->
                parent == oldTip || case validatedKind old of
                    Content oldParent -> parent == oldParent
                    _ -> False
            _ -> False
        _ -> False
