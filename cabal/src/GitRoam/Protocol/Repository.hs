module GitRoam.Protocol.Repository (
    ManagedState,
    StateProblem (..),
    TransitionProblem (..),
    validateManagedState,
    validateOrdinaryTransition,
    managedRefs,
    managedHistory,
    retainedCheckpoints,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity

data ManagedState = ManagedState ValidatedHistory (Map NodeId ObjectId) (Map NodeId (Set ObjectId))
    deriving (Eq, Show)

data StateProblem
    = UnknownNodeTip NodeId ObjectId
    | RefIdentityMismatch NodeId NodeId ObjectId
    | MissingDependencyBranch ObjectId NodeId ObjectId
    | DependencyVersionNotRetained ObjectId NodeId ObjectId
    deriving (Eq, Show)

data TransitionProblem
    = NodeBranchRemoved NodeId
    | NodeRootChanged NodeId ObjectId ObjectId
    | CheckpointsDiscarded NodeId (Set ObjectId)
    deriving (Eq, Show)

managedRefs :: ManagedState -> Map NodeId ObjectId
managedRefs (ManagedState _ refs _) = refs

managedHistory :: ManagedState -> ValidatedHistory
managedHistory (ManagedState history _ _) = history

retainedCheckpoints :: ManagedState -> Map NodeId (Set ObjectId)
retainedCheckpoints (ManagedState _ _ retained) = retained

-- Validate the complete proposed set, independent of live refs or any Git command.
validateManagedState :: ValidatedHistory -> Map NodeId ObjectId -> Either [StateProblem] ManagedState
validateManagedState history refs =
    if null problems then Right (ManagedState history refs retained) else Left problems
  where
    retained = Map.map (either (const Set.empty) id . formalHistory history) refs
    identities = concatMap identity (Map.toList refs)
    identity (node, tip) = case lookupCommit history tip of
        Nothing -> [UnknownNodeTip node tip]
        Just value
            | validatedNode value /= node -> [RefIdentityMismatch node (validatedNode value) tip]
            | otherwise -> []
    dependencies = concatMap dependency $ Set.toList (Set.unions (Map.elems retained))
    dependency oid = case projectCheckpoint history oid of
        Right (Just version) -> concatMap (required oid) (Map.toList (versionDependencies version))
        _ -> [] -- All traversed Checkpoints belong to the private validated history.
    required from (node, oid) = case Map.lookup node retained of
        Nothing -> [MissingDependencyBranch from node oid]
        Just versions
            | not (Set.member oid versions) -> [DependencyVersionNotRetained from node oid]
            | otherwise -> []
    problems = identities ++ dependencies

-- Both states must first pass the same complete-state validator. This relation
-- deliberately permits non-FF Content edits and does not use Git ancestry.
validateOrdinaryTransition :: ManagedState -> ManagedState -> Either [TransitionProblem] ()
validateOrdinaryTransition before after = if null problems then Right () else Left problems
  where
    problems = concatMap preserved (Map.toList (managedRefs before))
    preserved (node, oldTip) = case Map.lookup node (managedRefs after) of
        Nothing -> [NodeBranchRemoved node]
        Just newTip ->
            let oldVersions = Map.findWithDefault Set.empty node (retainedCheckpoints before)
                newVersions = Map.findWithDefault Set.empty node (retainedCheckpoints after)
                lost = Set.difference oldVersions newVersions
                roots = case (lookupCommit (managedHistory before) oldTip, lookupCommit (managedHistory after) newTip) of
                    (Just old, Just new)
                        | validatedRoot old /= validatedRoot new ->
                            [NodeRootChanged node (validatedRoot old) (validatedRoot new)]
                    _ -> []
             in roots ++ [CheckpointsDiscarded node lost | not (Set.null lost)]
