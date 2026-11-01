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
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Inspect
import GitRoam.Git
import GitRoam.Git.Objects
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import System.Directory (createDirectory, removeDirectory)
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
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

configuration :: IO [(String, BS.ByteString)]
configuration = getExecutablePath >>= configurationFor

configurationFor :: FilePath -> IO [(String, BS.ByteString)]
configurationFor executable = do
    let quoted = "'" ++ concatMap (\c -> if c == '\'' then "'\\''" else [c]) executable ++ "' --reference-transaction"
    pure [("event", "reference-transaction"), ("command", Encoding.encodeUtf8 (Text.pack quoted)), ("enabled", "true")]

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
requireProtection directory = getExecutablePath >>= \executable -> requireProtectionFor executable directory

-- Explicit executable dependency for library/application runtimes; the CLI uses
-- its own executable, while Cabal integration tests supply their built tool.
requireProtectionFor :: FilePath -> FilePath -> IO (Either String ())
requireProtectionFor executable directory = runExceptT $ do
    expected <- lift (configurationFor executable)
    mapM_
        ( \(key, value) -> do
            local <- ExceptT (values directory True key)
            effective <- ExceptT (values directory False key)
            unless (local == [value] && effective == [value]) $
                throwE "Git-roam protection is missing, disabled or divergent; enable the matching executable before modifying history"
        )
        expected

enableProtection :: FilePath -> IO (Either String ())
enableProtection directory = withOperationLock directory $ runExceptT $ do
    version <- ExceptT (checked directory ["--version"])
    let numbers = case words (BSC.unpack version) of
            _ : _ : text : _ -> mapM readMaybe (take 2 (splitDot text)) :: Maybe [Int]
            _ -> Nothing
    unless (maybe False (>= [2, 54]) numbers) (throwE "Git >= 2.54 with configured named Hooks is required")
    expected <- lift configuration
    observed <- mapM (\(key, _) -> ExceptT (values directory False key)) expected
    if all null observed
        then
            mapM_
                ( \(key, value) -> do
                    _ <- ExceptT (checked directory ["config", "--local", "--add", hookPrefix ++ key, Text.unpack (Encoding.decodeUtf8 value)])
                    pure ()
                )
                expected
        else ExceptT (requireProtection directory)
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
    expected <- lift configuration
    observed <- mapM (\(key, _) -> ExceptT (values directory False key)) expected
    unless (all null observed) $ do
        ExceptT (requireProtection directory)
        mapM_
            ( \(key, _) -> do
                _ <- ExceptT (checked directory ["config", "--local", "--unset-all", hookPrefix ++ key])
                pure ()
            )
            expected

-- Prepared sees actual old refs, even when an unchecked update reports zero old.
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
            raw <- ExceptT (checked directory ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"])
            before <- Map.fromList . concat <$> mapM (decodeRef format) (BSC.lines raw)
            after <- foldM (apply format before) before updates
            -- Local Content rewrites keep the same formal set and dependencies.
            local <- case updates of
                [(node, _)] -> do
                    let old = before Map.! node
                        new = after Map.! node
                    loaded <- lift (validateHistory format (nativeHistorySource native directory format []) [old, new])
                    case loaded of
                        Left problem -> throwE (show problem)
                        Right history -> do
                            let formal tip = either (const Nothing) Just (formalHistory history tip)
                                sameRoot = (validatedRoot <$> lookupCommit history old) == (validatedRoot <$> lookupCommit history new)
                            let unchanged = sameRoot && formal old == formal new
                            when unchanged $ do
                                evidence <- ExceptT (checked directory ["--no-replace-objects", "rev-list", "--objects", "--no-object-names", "--missing=print", BSC.unpack (objectIdBytes new), "--"])
                                when (any (BS.isPrefixOf "?") (BSC.lines evidence)) (throwE "Content history has missing objects")
                            pure unchanged
                _ -> pure False
            unless local $ do
                old <- lift (validateCandidate native directory before) >>= either (throwE . show) pure
                new <- lift (validateCandidate native directory after) >>= either (throwE . show) pure
                either (throwE . show) pure (validateOrdinaryTransition old new)
  where
    parseUpdate row = case BSC.words row of
        [_old, new, ref] -> case BS.stripPrefix "refs/heads/" ref >>= either (const Nothing) Just . parseNodeId of
            Nothing -> Right Nothing
            Just node -> Right (Just (node, new))
        -- Symbolic HEAD transactions have 'ref:<target>' values; HEAD is unrelated.
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
        when (BS.all (== 48) bytes) (throwE "Node deletion requires an explicit Git-roam operation")
        oid <- either throwE pure (parseObjectId format bytes)
        pure (Map.insert node oid state)
