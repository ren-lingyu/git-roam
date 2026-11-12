{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Application.Inspect (
    InspectionReport (..),
    NodeView (..),
    WorktreeView (..),
    inspectState,
) where

import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import GitRoam.Application.Validation
import GitRoam.Git
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import GitRoam.Repository (repositoryObjectFormat)

data WorktreeView = WorktreeView
    { worktreePath :: BS.ByteString
    , worktreeNode :: Maybe NodeId
    , worktreeIsMain :: Bool
    }
    deriving (Eq, Show)

data NodeView = NodeView
    { viewNode :: NodeId
    , viewTip :: ObjectId
    , viewKind :: CommitKind
    , viewLatestCheckpoint :: Maybe ObjectId
    , viewContextParents :: [ObjectId]
    , viewCheckpointCount :: Int
    }
    deriving (Eq, Show)

data InspectionReport = InspectionReport
    { reportNodes :: [NodeView]
    , reportProblems :: [StateProblem]
    , reportWorktrees :: [WorktreeView]
    }
    deriving (Eq, Show)

-- Legacy check presentation remains until B6. No trusted state is exported
-- through this report; operations use Validation and their explicit preflight.
inspectState :: Git IO -> FilePath -> [(String, Maybe String)] -> Maybe NodeId -> IO (Either ValidationError InspectionReport)
inspectState git directory environment target =
    withValidationEvidence git directory environment target $ \evidence -> runExceptT $ do
        worktrees <- ExceptT (validationQuery git directory environment ["worktree", "list", "--porcelain", "-z"]) >>= parseWorktrees (repositoryObjectFormat (validationRepository evidence))
        let history = validationHistory evidence
            selected = validationRefs evidence
            problems = either id (const []) (validateManagedState history selected)
        views <- mapM (nodeView history) (Map.toList selected)
        pure (InspectionReport views problems worktrees)
  where
    nodeView history (node, tip) = do
        value <- maybe (throwE (InvalidGitOutput [] "Validated tip is absent")) pure (lookupCommit history tip)
        firstParents <- either (const (throwE (InvalidGitOutput [] "First-parent history is unavailable"))) pure (firstParentHistory history tip)
        let checkpoints =
                [ oid
                | oid <- firstParents
                , Just ancestor <- [lookupCommit history oid]
                , Checkpoint _ _ <- [validatedKind ancestor]
                ]
            latest = case checkpoints of
                oid : _ -> Just oid
                [] -> Nothing
        context <- case latest of
            Nothing -> pure []
            Just oid -> either (const (throwE (InvalidGitOutput [] "Checkpoint context is unavailable"))) pure (contextParents history oid)
        pure (NodeView node tip (validatedKind value) latest context (length checkpoints))

    parseWorktrees format bytes = case Worktrees.decodeWorktrees format bytes of
        Left _ -> throwE (InvalidGitOutput ["worktree", "list"] bytes)
        Right records -> pure [WorktreeView (Worktrees.treePath r) (Worktrees.worktreeNode r) (Worktrees.treeMain r) | r <- records]
