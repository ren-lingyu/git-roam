{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Protection (
    enableProtection,
    disableProtection,
    requireProtection,
    requireProtectionFor,
    withOperationLock,
    ownHookBypass,
    evaluateTransaction,
) where

import Control.Exception (IOException, bracket, try)
import Control.Monad (foldM, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Inspect as Inspection
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History (CommitKind (..), lookupCommit, validatedKind)
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository (ManagedState, managedHistory, validateOrdinaryTransition)
import GitRoam.Repository
import System.Directory (createDirectory, doesPathExist, removeDirectory)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, takeFileName, (</>))
import Text.Read (readMaybe)

hookPrefix :: String
hookPrefix = "hook.git-roam-reference-transaction."

ownHookBypass :: [String]
ownHookBypass = ["-c", hookPrefix ++ "enabled=false"]

native :: Git IO
native = nativeGit defaultGitExecutable

call :: FilePath -> [String] -> IO (Either String GitResult)
call directory arguments = do
    result <- runGit native (GitInvocation directory arguments BS.empty readOnlyEnvironment)
    pure (either (Left . show) Right result)

checked :: FilePath -> [String] -> IO (Either String BS.ByteString)
checked directory arguments = do
    result <- call directory arguments
    pure $
        result >>= \value ->
            if gitExitCode value == ExitSuccess
                then Right (gitStdout value)
                else Left (show arguments ++ ": " ++ show (gitStderr value))

withOperationLock :: FilePath -> IO (Either String a) -> IO (Either String a)
withOperationLock directory action = do
    found <- inspectRepository native directory readOnlyEnvironment
    case found of
        Left problem -> pure (Left (show problem))
        Right repository -> case Encoding.decodeUtf8' (repositoryCommonDirectory repository) of
            Left _ -> pure (Left "Cannot safely address the common Git directory with this filesystem encoding")
            Right path -> do
                let lock = Text.unpack path </> "git-roam.operation.lock"
                acquired <- try (createDirectory lock) :: IO (Either IOException ())
                case acquired of
                    Left _ -> pure (Left "Repository operation lock is busy or unavailable; no stale lock is removed automatically")
                    Right () -> bracket (pure ()) (const (removeDirectory lock)) (const action)

-- Let Git resolve the hook through the environment's PATH, as GAW does.
-- The configured command is independent of the Nix store path of the caller.
configuration :: [(String, BS.ByteString)]
configuration = [("event", "reference-transaction"), ("command", "git-roam --reference-transaction"), ("enabled", "true")]

-- Only the exact shell-quoted command produced by older Git-roam releases is
-- eligible for migration. Other hook commands are never silently overwritten.
legacyHookCommand :: BS.ByteString -> Bool
legacyHookCommand bytes = case Encoding.decodeUtf8' bytes of
    Left _ -> False
    Right command -> case Text.stripPrefix "'" command >>= Text.stripSuffix "' --reference-transaction" of
        Nothing -> False
        Just escaped ->
            let path = Text.replace "'\\''" "'" escaped
             in command == "'" <> Text.replace "'" "'\\''" path <> "' --reference-transaction"
                    && isAbsolute (Text.unpack path)
                    && takeFileName (Text.unpack path) == "git-roam"

values :: FilePath -> Bool -> String -> IO (Either String [BS.ByteString])
values directory local key = do
    outcome <- call directory (["config"] ++ ["--local" | local] ++ ["--null", "--get-all", hookPrefix ++ key])
    pure $
        outcome >>= \result -> case gitExitCode result of
            ExitFailure 1 -> Right []
            ExitSuccess -> case BS.unsnoc (gitStdout result) of
                Just (body, 0) -> Right (BS.split 0 body)
                _ -> Left "Invalid Hook configuration output"
            _ -> Left (show (gitStderr result))

requireProtection :: FilePath -> IO (Either String ())
requireProtection directory =
    runExceptT $
        mapM_
            ( \(key, value) -> do
                local <- ExceptT (values directory True key)
                effective <- ExceptT (values directory False key)
                unless (local == [value] && effective == [value]) $
                    throwE "Git-roam protection is missing, disabled or divergent; run git roam enable and ensure git-roam is on PATH"
            )
            configuration

-- Preserve the application/test interface: the executable parameter is no
-- longer part of hook identity. Git resolves the canonical command via PATH.
requireProtectionFor :: FilePath -> FilePath -> IO (Either String ())
requireProtectionFor _ = requireProtection

enableProtection :: FilePath -> IO (Either String ())
enableProtection directory = withOperationLock directory $ runExceptT $ do
    version <- ExceptT (checked directory ["--version"])
    let numbers = case words (BSC.unpack version) of
            _ : _ : text : _ -> mapM readMaybe (take 2 (splitDot text)) :: Maybe [Int]
            _ -> Nothing
    unless (maybe False (>= [2, 54]) numbers) (throwE "Git >= 2.54 with configured named Hooks is required")
    local <- mapM (\(key, _) -> ExceptT (values directory True key)) configuration
    effective <- mapM (\(key, _) -> ExceptT (values directory False key)) configuration
    if all null local && all null effective
        then
            mapM_
                ( \(key, value) -> do
                    _ <- ExceptT (checked directory ["config", "--local", "--add", hookPrefix ++ key, Text.unpack (Encoding.decodeUtf8 value)])
                    pure ()
                )
                configuration
        else case (local, effective) of
            ( [["reference-transaction"], [command], ["true"]]
                , [["reference-transaction"], [effectiveCommand], ["true"]]
                ) | command == effectiveCommand && legacyHookCommand command -> do
                    -- Change only the command; never temporarily disable the hook.
                    _ <- ExceptT (checked directory ["config", "--local", "--replace-all", hookPrefix ++ "command", "git-roam --reference-transaction"])
                    pure ()
            _ -> ExceptT (requireProtection directory)
    ExceptT (requireProtection directory)
  where
    splitDot text = case break (== '.') text of
        (part, []) -> [part]
        (part, _ : rest) -> part : splitDot rest

disableProtection :: FilePath -> IO (Either String ())
disableProtection directory = withOperationLock directory $ runExceptT $ do
    repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository native directory readOnlyEnvironment))
    bytes <- ExceptT (checked directory ["worktree", "list", "--porcelain", "-z"])
    records <- either throwE pure (Worktrees.decodeWorktrees (repositoryObjectFormat repository) bytes)
    let nodes = [node | record <- records, not (Worktrees.treeMain record), Just node <- [Worktrees.worktreeNode record]]
    unless (null nodes) (throwE "Undeploy all Node linked worktrees before disabling protection")
    observed <- mapM (\(key, _) -> ExceptT (values directory False key)) configuration
    unless (all null observed) $ do
        ExceptT (requireProtection directory)
        mapM_
            ( \(key, _) -> do
                _ <- ExceptT (checked directory ["config", "--local", "--unset-all", hookPrefix ++ key])
                pure ()
            )
            configuration

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
            after <- foldM (apply repository before) before updates
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
        [old, new, ref] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> Right Nothing
            Just node -> Right (Just (node, (old, new)))
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

    apply repository before state (node, (old, bytes)) = do
        let format = repositoryObjectFormat repository
        unless (Map.member node before) (throwE "New Node branches require a controlled Git-roam operation")
        if bytes == BS.replicate (objectIdLength format) 48
            then do
                previous <- either (const (throwE deletionRefused)) pure (parseObjectId format old)
                unless (Map.lookup node before == Just previous) (throwE deletionRefused)
                pruning <- lift (retainedPackedRef directory repository node previous)
                unless pruning (throwE deletionRefused)
                pure state
            else do
                oid <- either throwE pure (parseObjectId format bytes)
                pure (Map.insert node oid state)

    deletionRefused = "Node deletion requires an explicit Git-roam operation"

-- Git's files backend commits packed refs and releases packed-refs.lock before
-- pruning redundant loose refs. Real deletions hold that lock during prepared,
-- including the nested packed transaction, where old OIDs can be zero. Matching
-- packed contents alone cannot distinguish those deletions from loose pruning.
-- Keep the logical ref unchanged only with matching old, loose and packed OIDs;
-- unknown backends, unreadable evidence and any packed lock fail closed.
retainedPackedRef :: FilePath -> Repository -> NodeId -> ObjectId -> IO Bool
retainedPackedRef directory repository node oid = do
    backend <- checked directory ["rev-parse", "--show-ref-format"]
    if backend /= Right "files\n"
        then pure False
        else do
            outcome <- try inspect :: IO (Either IOException Bool)
            pure (either (const False) id outcome)
  where
    inspect = case Encoding.decodeUtf8' (repositoryCommonDirectory repository) of
        Left _ -> pure False
        Right common -> do
            let root = Text.unpack common
                ref = "refs/heads/" <> nodeIdBytes node
                lock = root </> "packed-refs.lock"
            locked <- doesPathExist lock
            if locked
                then pure False
                else do
                    loose <- BS.readFile (root </> "refs" </> "heads" </> BSC.unpack (nodeIdBytes node))
                    packed <- BS.readFile (root </> "packed-refs")
                    stillLocked <- doesPathExist lock
                    let packedValues = [value | row <- BSC.lines packed, [value, name] <- [BSC.words row], name == ref]
                    pure (not stillLocked && BSC.lines loose == [objectIdBytes oid] && packedValues == [objectIdBytes oid])

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
