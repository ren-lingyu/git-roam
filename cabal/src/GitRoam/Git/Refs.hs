{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Refs (
    NodeRefScope (..),
    NodeRefObservation (..),
    RefReadError (..),
    localNode,
    remoteNodeCandidate,
    nodeRefArguments,
    decodeNodeRefs,
    readNodeRefs,
) where

import Control.Monad (foldM)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Set as Set
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Exit (ExitCode (..))

data NodeRefScope = LocalNodes | LocalAndRemoteNodes
    deriving (Eq, Show)

-- The remote prefix is only a ref-path component, not a verified remote name.
-- Keep the complete ref and symbolic target; callers decide which facts are safe
-- to use for their operation. Ordinary branches are not Node observations.
data NodeRefObservation = NodeRefObservation
    { observedRef :: BS.ByteString
    , observedNode :: NodeId
    , observedTip :: ObjectId
    , observedSymbolic :: BS.ByteString
    , observedRemotePrefix :: Maybe BS.ByteString
    }
    deriving (Eq, Show)

data RefReadError
    = RefTransportFailure GitError
    | RefCommandFailure GitResult
    | MalformedRefOutput BS.ByteString
    | InvalidRefObject BS.ByteString String
    | DuplicateNodeRef BS.ByteString
    deriving (Eq, Show)

localNode :: BS.ByteString -> Maybe NodeId
localNode name = BS.stripPrefix "refs/heads/" name >>= either (const Nothing) Just . parseNodeId

-- Preserve Deploy's suffix rule without interpreting arbitrary fetch refspecs.
remoteNodeCandidate :: BS.ByteString -> Maybe (BS.ByteString, NodeId)
remoteNodeCandidate ref = do
    suffix <- BS.stripPrefix "refs/remotes/" ref
    let (prefix, uuid) = BSC.breakEnd (== '/') suffix
    if BS.null prefix
        then Nothing
        else do
            node <- either (const Nothing) Just (parseNodeId uuid)
            pure (BS.init prefix, node)

nodeRefArguments :: NodeRefScope -> [String]
nodeRefArguments scope =
    ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)", "refs/heads/"]
        ++ ["refs/remotes/" | scope == LocalAndRemoteNodes]

-- Preserve observation order and reject duplicate relevant refs instead of
-- silently losing conflicting evidence in a Map. Ignore OIDs of ordinary refs,
-- as existing callers do, but require every row to have the expected framing.
decodeNodeRefs :: ObjectFormat -> NodeRefScope -> BS.ByteString -> Either RefReadError [NodeRefObservation]
decodeNodeRefs format scope bytes = reverse . snd <$> foldM decode (Set.empty, []) (BSC.lines bytes)
  where
    decode (seen, records) row = case BS.split 0 row of
        [name, oid, symbolic] -> case classify name of
            Nothing -> Right (seen, records)
            Just (node, remote) -> do
                if Set.member name seen then Left (DuplicateNodeRef row) else Right ()
                object <- either (Left . InvalidRefObject row) Right (parseObjectId format oid)
                Right (Set.insert name seen, NodeRefObservation name node object symbolic remote : records)
        _ -> Left (MalformedRefOutput row)
    classify name = case localNode name of
        Just node -> Just (node, Nothing)
        Nothing | scope == LocalAndRemoteNodes -> do
            (prefix, node) <- remoteNodeCandidate name
            Just (node, Just prefix)
        Nothing -> Nothing

-- One native ref enumeration. The caller supplies its own environment policy;
-- no discovery, history, worktree or network query is hidden in this reader.
-- for-each-ref warnings can indicate omitted/broken refs, so retain them as a
-- command failure even when Git exits successfully.
readNodeRefs :: Git IO -> FilePath -> [(String, Maybe String)] -> ObjectFormat -> NodeRefScope -> IO (Either RefReadError [NodeRefObservation])
readNodeRefs git directory environment format scope = do
    outcome <- runGit git (GitInvocation directory ("--no-replace-objects" : nodeRefArguments scope) BS.empty environment)
    pure $ case outcome of
        Left problem -> Left (RefTransportFailure problem)
        Right result
            | gitExitCode result == ExitSuccess && BS.null (gitStderr result) -> decodeNodeRefs format scope (gitStdout result)
            | otherwise -> Left (RefCommandFailure result)
