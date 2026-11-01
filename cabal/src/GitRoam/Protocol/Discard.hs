module GitRoam.Protocol.Discard (
    DiscardImpact (..),
    NodeDiscard (..),
    DiscardReason (..),
    computeDiscard,
) where

import Control.Monad (forM, unless)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository

-- Diagnostic values only, never authorization or an executable mutation plan.
data DiscardReason = ExplicitTarget | FormalSuccessor ObjectId | DependencySuccessor ObjectId
    deriving (Eq, Ord, Show)
data NodeDiscard = NodeDiscard
    { discardNode :: NodeId
    , discardOldTip :: ObjectId
    , discardNewTip :: Maybe ObjectId
    , discardNodeVersions :: Set ObjectId
    , discardRemainingMaxima :: Set ObjectId
    , discardLostContent :: Maybe (Set ObjectId)
    }
    deriving (Eq, Show)
data DiscardImpact = DiscardImpact
    { discardTargets :: Set ObjectId
    , discardVersions :: Set ObjectId
    , discardReasons :: Map ObjectId (Set DiscardReason)
    , discardNodes :: [NodeDiscard]
    , discardCandidate :: Maybe ManagedState
    }
    deriving (Eq, Show)

computeDiscard :: ManagedState -> Set ObjectId -> Either String DiscardImpact
computeDiscard before targets = do
    unless (not (Set.null targets) && targets `Set.isSubsetOf` retained) $
        Left "Every discard target must be an explicitly selected, currently retained Checkpoint"
    versions <- Map.fromList <$> mapM version (Set.toList retained)
    let successors = Map.fromListWith Set.union [(parent, Set.singleton oid) | (oid, v) <- Map.toList versions, parent <- Set.toList (predecessors v)]
        removed = close successors Set.empty (Set.toList targets)
        remaining = retained `Set.difference` removed
        affected = Map.filter (not . Set.null) (Map.map (`Set.intersection` removed) (retainedCheckpoints before))
        reasons oid v =
            Set.fromList $
                [ExplicitTarget | Set.member oid targets]
                    ++ [FormalSuccessor p | p <- Set.toList (versionHistory v `Set.intersection` removed)]
                    ++ [DependencySuccessor p | p <- Map.elems (versionDependencies v), Set.member p removed]
    changes <- forM (Map.toList affected) $ \(node, lost) -> do
        old <- maybe (Left "Validated Node has no branch") Right (Map.lookup node (managedRefs before))
        value <- maybe (Left "Validated Node has no tip object") Right (lookupCommit history old)
        let kept = Map.findWithDefault Set.empty node (retainedCheckpoints before) `Set.difference` removed
            nonmaximal = Set.unions [versionHistory v | oid <- Set.toList kept, Just v <- [Map.lookup oid versions]]
            maxima = kept `Set.difference` nonmaximal
            new = case Set.toList maxima of
                [] -> Just (validatedRoot value)
                [oid] -> Just oid
                _ -> Nothing
        pure (NodeDiscard node old new lost maxima Nothing)
    candidate <-
        if any ((== Nothing) . discardNewTip) changes
            then pure Nothing
            else do
                let refs = Map.union (Map.fromList [(discardNode n, tip) | n <- changes, Just tip <- [discardNewTip n]]) (managedRefs before)
                state <- either (Left . show) Right (validateManagedState history refs)
                unless (Set.unions (Map.elems (retainedCheckpoints state)) == remaining) (Left "Candidate does not preserve exactly the required remaining Checkpoints")
                checkNodeRetention remaining state
                pure (Just state)
    oldContent <- contentReachable (Map.elems (managedRefs before))
    lostContent <- case candidate of
        Nothing -> pure Nothing
        Just after -> Just . (oldContent `Set.difference`) <$> contentReachable (Map.elems (managedRefs after))
    let withContent n = n{discardLostContent = fmap (Set.filter (belongs (discardNode n))) lostContent}
    pure (DiscardImpact targets removed (Map.mapWithKey reasons (Map.restrictKeys versions removed)) (map withContent changes) candidate)
  where
    history = managedHistory before
    retained = Set.unions (Map.elems (retainedCheckpoints before))
    version oid = case projectCheckpoint history oid of
        Right (Just value) -> Right (oid, value)
        _ -> Left "Retained Checkpoint is absent from validated history"
    predecessors v = Set.union (versionHistory v) (Set.fromList (Map.elems (versionDependencies v)))
    close _ seen [] = seen
    close successors seen (oid : rest)
        | Set.member oid seen = close successors seen rest
        | otherwise = close successors (Set.insert oid seen) (Set.toList (Map.findWithDefault Set.empty oid successors) ++ rest)
    belongs node oid = maybe False ((== node) . validatedNode) (lookupCommit history oid)
    checkNodeRetention remaining state = mapM_ (\(node, old) -> unless (Map.lookup node (retainedCheckpoints state) == Just (old `Set.intersection` remaining)) (Left "Candidate changes another Node's retained history")) (Map.toList (retainedCheckpoints before))
    contentReachable = walk Set.empty Set.empty
    walk _ contents [] = Right contents
    walk seen contents (oid : rest)
        | Set.member oid seen = walk seen contents rest
        | otherwise = case lookupCommit history oid of
            Nothing -> Left "Reachable object is absent from validated history"
            Just value -> case validatedKind value of
                Root -> walk (Set.insert oid seen) contents rest
                Content parent _ -> walk (Set.insert oid seen) (Set.insert oid contents) (parent : rest)
                Checkpoint parents ->
                    walk
                        (Set.insert oid seen)
                        contents
                        (mainPredecessor parents : contentTip parents : Set.toList (mergedPredecessors parents) ++ Map.elems (directDependencies parents) ++ rest)
