{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Protocol.History (
    ValidatedHistory,
    ValidatedCommit,
    CommitKind (..),
    CheckpointParents (..),
    FormalVersion (..),
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
    projectCheckpoint,
    formalHistory,
    isFormalAncestor,
    isKnowledgeAncestor,
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

-- Constructors of the validated containers are private; accessors are functions,
-- not exported record fields that could be used to replace validated values.
newtype ValidatedHistory = ValidatedHistory (Map ObjectId ValidatedCommit)
    deriving (Eq, Show)

data ValidatedCommit = ValidatedCommit ObjectId NodeId ObjectId ObjectId CommitKind
    deriving (Eq, Show)

data CommitKind
    = Root
    | Content ObjectId ObjectId -- immediate parent, editing-chain base (Root/K)
    | Checkpoint CheckpointParents
    deriving (Eq, Show)

data CheckpointParents = CheckpointParents
    { mainPredecessor :: ObjectId
    , contentTip :: ObjectId
    , mergedPredecessors :: Set ObjectId
    , directDependencies :: Map NodeId ObjectId
    }
    deriving (Eq, Show)

-- A projection view, not an authority for mutating validated history.
data FormalVersion = FormalVersion
    { versionOid :: ObjectId
    , versionNode :: NodeId
    , versionTree :: ObjectId
    , versionHistory :: Set ObjectId
    , versionDependencies :: Map NodeId ObjectId
    }
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
    | InvalidMainPredecessor ObjectId ObjectId
    | InvalidContentTip ObjectId ObjectId
    | ContentBaseMismatch ObjectId ObjectId ObjectId
    | CheckpointTreeMismatch ObjectId ObjectId
    | ExtraParentNotCheckpoint ObjectId ObjectId
    | DuplicateDependency ObjectId NodeId
    | CyclicHistory ObjectId
    deriving (Eq, Show)

data QueryError = UnknownCommit ObjectId | ExpectedCheckpoint ObjectId
    deriving (Eq, Show)

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

-- Each invocation memoizes immutable commits and identity-bearing trees by OID.
-- Payload blob contents have no protocol semantics and are not interpreted here.
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
                        let base = case validatedKind parent of
                                Content _ anchor -> anchor
                                _ -> validatedOid parent
                        pure (validatedRoot parent, Content (validatedOid parent) base)
                    q : w : extra -> do
                        sameNode oid node q
                        sameNode oid node w
                        case validatedKind q of
                            Content _ _ -> throwE (InvalidMainPredecessor oid (validatedOid q))
                            _ -> pure ()
                        case validatedKind w of
                            Content _ base ->
                                unless (base == validatedOid q) $
                                    throwE (ContentBaseMismatch oid (validatedOid q) base)
                            _ -> throwE (InvalidContentTip oid (validatedOid w))
                        unless (tree == validatedTree w) $
                            throwE (CheckpointTreeMismatch oid (validatedOid w))
                        (merged, dependencies) <- foldM (classify oid node) (Set.empty, Map.empty) extra
                        pure
                            ( validatedRoot q
                            , Checkpoint (CheckpointParents (validatedOid q) (validatedOid w) merged dependencies)
                            )
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

    classify oid node (merged, dependencies) parent = do
        case validatedKind parent of
            Checkpoint _ -> pure ()
            _ -> throwE (ExtraParentNotCheckpoint oid (validatedOid parent))
        if validatedNode parent == node
            then pure (Set.insert (validatedOid parent) merged, dependencies)
            else do
                when (Map.member (validatedNode parent) dependencies) $
                    throwE (DuplicateDependency oid (validatedNode parent))
                pure (merged, Map.insert (validatedNode parent) (validatedOid parent) dependencies)

-- The formal dependency set is undefined for Content, not an empty declaration.
projectCheckpoint :: ValidatedHistory -> ObjectId -> Either QueryError (Maybe FormalVersion)
projectCheckpoint history oid = do
    commit <- requireCommit history oid
    case validatedKind commit of
        Checkpoint parents -> do
            q <- requireCommit history (mainPredecessor parents)
            let prior = case validatedKind q of
                    Checkpoint _ -> Set.singleton (validatedOid q)
                    _ -> Set.empty
            pure $
                Just $
                    FormalVersion
                        oid
                        (validatedNode commit)
                        (validatedTree commit)
                        (Set.union prior (mergedPredecessors parents))
                        (directDependencies parents)
        _ -> pure Nothing

formalHistory :: ValidatedHistory -> ObjectId -> Either QueryError (Set ObjectId)
formalHistory history tip = walk Set.empty Set.empty [tip]
  where
    walk _ result [] = Right result
    walk seen result (oid : rest)
        | Set.member oid seen = walk seen result rest
        | otherwise = do
            commit <- requireCommit history oid
            let seen' = Set.insert oid seen
            case validatedKind commit of
                Root -> walk seen' result rest
                Content parent _ -> walk seen' result (parent : rest)
                Checkpoint parents ->
                    walk seen' (Set.insert oid result) $
                        mainPredecessor parents : Set.toList (mergedPredecessors parents) ++ rest

isFormalAncestor :: ValidatedHistory -> ObjectId -> ObjectId -> Either QueryError Bool
isFormalAncestor history ancestor descendant = do
    a <- requireCheckpoint history ancestor
    b <- requireCheckpoint history descendant
    if validatedNode a /= validatedNode b
        then pure False
        else Set.member ancestor <$> formalHistory history descendant

isKnowledgeAncestor :: ValidatedHistory -> ObjectId -> ObjectId -> Either QueryError Bool
isKnowledgeAncestor history ancestor descendant = do
    _ <- requireCheckpoint history ancestor
    _ <- requireCheckpoint history descendant
    walk Set.empty [descendant]
  where
    walk _ [] = Right False
    walk seen (oid : rest)
        | oid == ancestor = Right True
        | Set.member oid seen = walk seen rest
        | otherwise = do
            projected <- projectCheckpoint history oid
            case projected of
                Just version ->
                    walk (Set.insert oid seen) $
                        Set.toList (versionHistory version) ++ Map.elems (versionDependencies version) ++ rest
                Nothing -> Left (ExpectedCheckpoint oid)

requireCommit :: ValidatedHistory -> ObjectId -> Either QueryError ValidatedCommit
requireCommit history oid = maybe (Left (UnknownCommit oid)) Right (lookupCommit history oid)

requireCheckpoint :: ValidatedHistory -> ObjectId -> Either QueryError ValidatedCommit
requireCheckpoint history oid = do
    commit <- requireCommit history oid
    case validatedKind commit of
        Checkpoint _ -> Right commit
        _ -> Left (ExpectedCheckpoint oid)
