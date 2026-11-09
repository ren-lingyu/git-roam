module GitRoam.Protocol.Repository (
    ManagedState,
    StateProblem (..),
    TransitionProblem (..),
    validateManagedState,
    validateOrdinaryTransition,
    managedRefs,
    managedHistory,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity

data ManagedState = ManagedState ValidatedHistory (Map NodeId ObjectId)
    deriving (Eq, Show)

data StateProblem
    = UnknownNodeTip NodeId ObjectId
    | RefIdentityMismatch NodeId NodeId ObjectId
    deriving (Eq, Show)

data TransitionProblem
    = NodeBranchRemoved NodeId
    | NodeRootChanged NodeId ObjectId ObjectId
    deriving (Eq, Show)

managedRefs :: ManagedState -> Map NodeId ObjectId
managedRefs (ManagedState _ refs) = refs

managedHistory :: ManagedState -> ValidatedHistory
managedHistory (ManagedState history _) = history

-- The caller supplies only local managed refs. Referenced context commits do
-- not need to remain reachable from another Node's current branch.
validateManagedState :: ValidatedHistory -> Map NodeId ObjectId -> Either [StateProblem] ManagedState
validateManagedState history refs =
    if null problems then Right (ManagedState history refs) else Left problems
  where
    problems = concatMap identity (Map.toList refs)
    identity (node, tip) = case lookupCommit history tip of
        Nothing -> [UnknownNodeTip node tip]
        Just value
            | validatedNode value /= node -> [RefIdentityMismatch node (validatedNode value) tip]
            | otherwise -> []

-- Ordinary history rewrites may drop old Content and Checkpoints. A protected
-- ref still cannot silently disappear or acquire an unrelated Root identity.
validateOrdinaryTransition :: ManagedState -> ManagedState -> Either [TransitionProblem] ()
validateOrdinaryTransition before after =
    if null problems then Right () else Left problems
  where
    problems = concatMap preserved (Map.toList (managedRefs before))
    preserved (node, oldTip) = case Map.lookup node (managedRefs after) of
        Nothing -> [NodeBranchRemoved node]
        Just newTip -> case (lookupCommit (managedHistory before) oldTip, lookupCommit (managedHistory after) newTip) of
            (Just old, Just new)
                | validatedRoot old /= validatedRoot new ->
                    [NodeRootChanged node (validatedRoot old) (validatedRoot new)]
            _ -> []
