{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Undeploy (undeploy, UndeploymentResult (..), UndeploymentFailure (..)) where

import Control.Exception (IOException, try)
import Control.Monad (forM_, unless)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import Data.IORef (modifyIORef', newIORef, readIORef)
import GitRoam.Application.Inspect (inspectState, reportManagedState)
import GitRoam.Application.Protection (requireProtectionFor)
import GitRoam.Application.Worktree
import GitRoam.Git
import GitRoam.Git.Objects (readOnlyEnvironment)
import GitRoam.Git.Worktrees
import GitRoam.ObjectId (ObjectFormat)
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository
import GitRoam.Worktree.Paths (decodePath)

data UndeploymentResult = UndeploymentResult
    { removedWorktrees :: [(NodeId, BS.ByteString)]
    , retainedMainNodes :: [(NodeId, BS.ByteString)]
    }
    deriving (Eq, Show)
data UndeploymentFailure = UndeploymentFailure String [String] deriving (Eq, Show)

loadState :: Git IO -> FilePath -> IO (Either String ManagedState)
loadState git directory = do
    outcome <- inspectState git directory [] Nothing
    pure $ case outcome of
        Left problem -> Left (show problem)
        Right report -> either (Left . show) Right (reportManagedState report)

-- Removal changes deployment only. All targets are checked before the first
-- native command; after execution starts, failures stop without re-creating or
-- resetting anything. Subsequent commands run from the surviving common dir.
undeploy :: FilePath -> Git IO -> FilePath -> IO (Either UndeploymentFailure UndeploymentResult)
undeploy executable git directory = do
    completed <- newIORef []
    outcome <- try $ withProtectedSession executable git directory $ \session -> do
        prepared <- runExceptT $ do
            repository <- ExceptT (fmap (either (Left . show) Right) (inspectRepository git directory readOnlyEnvironment))
            common <- lift (decodePath (repositoryCommonDirectory repository))
            state <- ExceptT (loadState git common)
            plan <- ExceptT (planRemoval git common state)
            pure (repository, common, state, plan)
        case prepared of
            Left problem -> pure (Left problem)
            Right (repository, common, state, plan) -> do
                applied <- runExceptT $ do
                    forM_ (removalTargets plan) $ \record -> do
                        node <- maybe (throwE "Non-Node removal target") pure (worktreeNode record)
                        ExceptT (removePlannedWorktree session plan node)
                        lift (modifyIORef' completed (++ [(node, treePath record)]))
                    actual <- ExceptT (loadState git common)
                    unless (managedRefs actual == managedRefs state) (throwE "Managed refs changed during undeployment")
                    final <- ExceptT (listWorktrees git common (repositoryObjectFormat repository))
                    unless
                        (null [r | r <- final, not (treeMain r), worktreeNode r /= Nothing])
                        (throwE "Node linked worktrees remain; undeployment is incomplete")
                    ExceptT (requireProtectionFor executable common)
                    pure (UndeploymentResult [] [(node, treePath record) | record <- final, treeMain record, Just node <- [worktreeNode record]])
                removed <- readIORef completed
                case applied of
                    Right result -> pure (Right (Right (result{removedWorktrees = removed})))
                    Left problem -> do
                        details <- remainingState git common (repositoryObjectFormat repository)
                        pure (Right (Left (UndeploymentFailure problem (("Confirmed removals: " ++ show removed) : details))))
    case outcome of
        Left problem -> do
            removed <- readIORef completed
            pure
                ( Left
                    ( UndeploymentFailure
                        (show (problem :: IOException))
                        ["Confirmed removals: " ++ show removed, "Operation interrupted; inspect actual refs/worktrees. No rollback was attempted."]
                    )
                )
        Right (Left problem) -> pure (Left (UndeploymentFailure problem []))
        Right (Right result) -> pure result

remainingState :: Git IO -> FilePath -> ObjectFormat -> IO [String]
remainingState git directory format = do
    records <- listWorktrees git directory format
    state <- loadState git directory
    pure
        ( [ case records of
                Left problem -> "Actual worktree state unavailable: " ++ problem
                Right values -> "Remaining Node worktrees: " ++ show [(worktreeNode r, treePath r, treeMain r, treeLocked r, treePrunable r) | r <- values, worktreeNode r /= Nothing]
          ]
            ++ [ case state of
                    Left problem -> "Actual managed state could not be validated: " ++ problem
                    Right actual -> "Actual managed refs: " ++ show (managedRefs actual)
               ]
        )
