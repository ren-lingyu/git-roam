{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Protocol.History (
    ValidatedHistory,
    ValidatedCommit,
    CommitKind (..),
    TreeProblem (..),
    HistoryError (..),
    QueryError (..),
    validateHistory,
    lookupCommit,
    validatedOid,
    validatedNode,
    validatedRoot,
    validatedTree,
    validatedKind,
    firstParentHistory,
    contextParents,
    reachableHistory,
    reachableHistoryFrom,
) where

import Control.Monad (foldM, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (runExceptT, throwE)
import Control.Monad.Trans.State.Strict (evalStateT, gets, modify')
import qualified Data.ByteString as BS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects

-- Private constructors prevent callers from manufacturing validated commits.
newtype ValidatedHistory = ValidatedHistory (Map ObjectId ValidatedCommit)
    deriving (Eq, Show)

data ValidatedCommit = ValidatedCommit ObjectId NodeId ObjectId ObjectId CommitKind
    deriving (Eq, Show)

-- The first parent alone carries a Node's own history and Root identity.
-- A multi-parent Checkpoint records explicit context, never inherited context.
data CommitKind
    = Root
    | Content ObjectId
    | Checkpoint ObjectId [ObjectId]
    deriving (Eq, Show)

data TreeProblem
    = InvalidEntryName BS.ByteString
    | DuplicateEntryName BS.ByteString
    | InvalidTopLevel
    | InvalidUuidDirectory BS.ByteString
    | MissingOrNonregularMarker
    | RootContainsContent
    deriving (Eq, Show)

data HistoryError
    = ObjectUnavailable ObjectId ObjectProblem
    | ObjectFormatMismatch ObjectId
    | InvalidNodeTree ObjectId TreeProblem
    | DuplicateParents ObjectId
    | IdentityChanged ObjectId NodeId NodeId
    | ConflictingRoots NodeId ObjectId ObjectId
    | CheckpointTreeMismatch ObjectId ObjectId
    | OverlappingContextTree ObjectId ObjectId
    | CyclicHistory ObjectId
    deriving (Eq, Show)

data QueryError = UnknownCommit ObjectId deriving (Eq, Show)

data ValidationState = ValidationState
    { commits :: Map ObjectId ValidatedCommit
    , trees :: Map ObjectId (NodeId, Bool)
    , treeObjects :: Map ObjectId [TreeEntry]
    , roots :: Map NodeId ObjectId
    , visiting :: Set ObjectId
    }

validatedOid :: ValidatedCommit -> ObjectId
validatedOid (ValidatedCommit oid _ _ _ _) = oid

validatedNode :: ValidatedCommit -> NodeId
validatedNode (ValidatedCommit _ node _ _ _) = node

validatedRoot :: ValidatedCommit -> ObjectId
validatedRoot (ValidatedCommit _ _ root _ _) = root

validatedTree :: ValidatedCommit -> ObjectId
validatedTree (ValidatedCommit _ _ _ tree _) = tree

validatedKind :: ValidatedCommit -> CommitKind
validatedKind (ValidatedCommit _ _ _ _ kind) = kind

lookupCommit :: ValidatedHistory -> ObjectId -> Maybe ValidatedCommit
lookupCommit (ValidatedHistory history) oid = Map.lookup oid history

-- Validate only the locally supplied starting points and their Git ancestors.
-- Immutable objects and identity-bearing trees are memoized per invocation.
validateHistory ::
    (Monad m) =>
    ObjectFormat ->
    HistorySource m ->
    [ObjectId] ->
    m (Either HistoryError ValidatedHistory)
validateHistory format source tips =
    evalStateT (runExceptT action) (ValidationState Map.empty Map.empty Map.empty Map.empty Set.empty)
  where
    action = do
        mapM_ visit tips
        ValidatedHistory <$> lift (gets commits)

    checkOid oid =
        unless (BS.length (objectIdBytes oid) == objectIdLength format) $
            throwE (ObjectFormatMismatch oid)

    readObject loader oid = do
        checkOid oid
        result <- lift (lift (loader oid))
        either (throwE . ObjectUnavailable oid) pure result

    readTree oid = do
        cached <- lift (gets (Map.lookup oid . treeObjects))
        case cached of
            Just entries -> pure entries
            Nothing -> do
                entries <- readObject (loadTree source) oid
                entriesValid oid entries
                lift (modify' (\state -> state{treeObjects = Map.insert oid entries (treeObjects state)}))
                pure entries

    nodeTree tree = do
        checkOid tree
        cached <- lift (gets (Map.lookup tree . trees))
        case cached of
            Just value -> pure value
            Nothing -> do
                top <- readTree tree
                (node, directory) <- case top of
                    [TreeEntry name Directory child] -> case parseNodeId name of
                        Right node -> pure (node, child)
                        Left _ -> throwE (InvalidNodeTree tree (InvalidUuidDirectory name))
                    _ -> throwE (InvalidNodeTree tree InvalidTopLevel)
                contents <- readTree directory
                case filter ((== ".roam") . entryName) contents of
                    [marker] | entryMode marker `elem` [RegularFile, ExecutableFile] -> pure ()
                    _ -> throwE (InvalidNodeTree tree MissingOrNonregularMarker)
                let value = (node, length contents == 1)
                lift (modify' (\state -> state{trees = Map.insert tree value (trees state)}))
                pure value

    entriesValid tree entries = do
        _ <- foldM step Set.empty entries
        pure ()
      where
        step seen entry = do
            let name = entryName entry
            when (BS.null name || name `elem` [".", ".."] || BS.any (`elem` [0, 47]) name) $
                throwE (InvalidNodeTree tree (InvalidEntryName name))
            when (Set.member name seen) $
                throwE (InvalidNodeTree tree (DuplicateEntryName name))
            checkOid (entryObject entry)
            pure (Set.insert name seen)

    visit oid = do
        checkOid oid
        cached <- lift (gets (Map.lookup oid . commits))
        case cached of
            Just value -> pure value
            Nothing -> do
                active <- lift (gets (Set.member oid . visiting))
                when active (throwE (CyclicHistory oid))
                lift (modify' (\state -> state{visiting = Set.insert oid (visiting state)}))
                object <- readObject (loadCommit source) oid
                let parents = commitParents object
                    tree = commitTree object
                when (length parents /= Set.size (Set.fromList parents)) $
                    throwE (DuplicateParents oid)
                (node, rootTree) <- nodeTree tree
                ancestors <- mapM visit parents
                (root, kind) <- case ancestors of
                    [] -> do
                        unless rootTree (throwE (InvalidNodeTree tree RootContainsContent))
                        pure (oid, Root)
                    [parent] -> do
                        sameNode oid node parent
                        pure (validatedRoot parent, Content (validatedOid parent))
                    parent : context -> do
                        sameNode oid node parent
                        unless (tree == validatedTree parent) $
                            throwE (CheckpointTreeMismatch oid (validatedOid parent))
                        -- A validated tree has exactly one top-level UUID
                        -- directory. Therefore path overlap is equivalent to
                        -- equal Node UUIDs; context trees need not be pairwise
                        -- disjoint from each other.
                        mapM_ (nonoverlapping oid node) context
                        pure (validatedRoot parent, Checkpoint (validatedOid parent) (map validatedOid context))
                knownRoot <- lift (gets (Map.lookup node . roots))
                case knownRoot of
                    Just other | other /= root -> throwE (ConflictingRoots node other root)
                    _ -> pure ()
                let value = ValidatedCommit oid node root tree kind
                lift $ modify' $ \state ->
                    state
                        { commits = Map.insert oid value (commits state)
                        , roots = Map.insert node root (roots state)
                        , visiting = Set.delete oid (visiting state)
                        }
                pure value

    sameNode oid node parent =
        unless (node == validatedNode parent) $
            throwE (IdentityChanged oid node (validatedNode parent))

    nonoverlapping oid node parent =
        when (node == validatedNode parent) $
            throwE (OverlappingContextTree oid (validatedOid parent))

-- Both queries follow only first-parent edges; their results are ordered
-- from the selected commit backwards, including the selected commit itself.
firstParentHistory :: ValidatedHistory -> ObjectId -> Either QueryError [ObjectId]
firstParentHistory history = go []
  where
    go accumulated oid = do
        value <- requireCommit history oid
        case validatedKind value of
            Root -> Right (reverse (oid : accumulated))
            Content parent -> go (oid : accumulated) parent
            Checkpoint parent _ -> go (oid : accumulated) parent

-- Direct context is a caller-selected ordered list, not a dependency mapping.
-- Ordinary Root/Content commits have no context.
contextParents :: ValidatedHistory -> ObjectId -> Either QueryError [ObjectId]
contextParents history oid = do
    value <- requireCommit history oid
    pure $ case validatedKind value of
        Checkpoint _ context -> context
        _ -> []

-- Ordinary Git reachability: this intentionally includes *all* parents.
reachableHistory :: ValidatedHistory -> ObjectId -> Either QueryError (Set ObjectId)
reachableHistory history oid = reachableHistoryFrom history [oid]

-- Multiple starting commits share one visited set, so common ancestry is
-- traversed only once.
reachableHistoryFrom :: ValidatedHistory -> [ObjectId] -> Either QueryError (Set ObjectId)
reachableHistoryFrom history starts = walk Set.empty starts
  where
    walk seen [] = Right seen
    walk seen (current : remaining)
        | Set.member current seen = walk seen remaining
        | otherwise = do
            value <- requireCommit history current
            let parents = case validatedKind value of
                    Root -> []
                    Content parent -> [parent]
                    Checkpoint parent context -> parent : context
            walk (Set.insert current seen) (parents ++ remaining)

requireCommit :: ValidatedHistory -> ObjectId -> Either QueryError ValidatedCommit
requireCommit history oid = maybe (Left (UnknownCommit oid)) Right (lookupCommit history oid)
