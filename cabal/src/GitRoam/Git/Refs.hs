{-# LANGUAGE OverloadedStrings #-}

module GitRoam.Git.Refs (
    NodeRefScope (..),
    NodeRefObservation (..),
    RefReadError (..),
    RefObservation (..),
    observationComplete,
    requireCompleteRefs,
    UpstreamConfig (..),
    readUpstreamConfig,
    UpstreamConfigObservation (..),
    UpstreamConfigProblem (..),
    decodeUpstreamConfig,
    localNode,
    remoteNodeCandidate,
    nodeRefArguments,
    decodeNodeRefs,
    readNodeRefs,
    refExists,
) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.Map.Strict as Map
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import System.Exit (ExitCode (..))

data NodeRefScope = LocalNodes | LocalAndRemoteNodes | LocalAndRemoteUpstreams
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
    , observedUpstream :: Maybe BS.ByteString
    , observedUpstreamRemote :: Maybe BS.ByteString
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

-- Successful rows and complete enumeration are separate facts. Strict callers
-- must explicitly require completeness; Status can retain reliable successes.
-- This describes Git's observable enumeration, not an exhaustive backend audit:
-- Git can silently omit dangling symrefs. Use refExists for exact-name occupancy.
data RefObservation = RefObservation
    { observationRefs :: [NodeRefObservation]
    , observationErrors :: [RefReadError]
    }
    deriving (Eq, Show)

observationComplete :: RefObservation -> Bool
observationComplete = null . observationErrors

requireCompleteRefs :: RefObservation -> Either RefReadError [NodeRefObservation]
requireCompleteRefs result = case observationErrors result of
    [] -> Right (observationRefs result)
    problem : _ -> Left problem

-- Exact-name occupancy is distinct from successful OID resolution. In
-- particular, native enumeration may omit a dangling symbolic reference.
refExists :: Git IO -> FilePath -> [(String, Maybe String)] -> BS.ByteString -> IO (Either RefReadError Bool)
refExists git directory environment ref = do
    result <- runGit git (GitInvocation directory ["refs", "exists", BSC.unpack ref] BS.empty environment)
    pure $ case result of
        Left problem -> Left (RefTransportFailure problem)
        Right value | gitExitCode value == ExitSuccess && BS.null (gitStdout value) && BS.null (gitStderr value) -> Right True
        Right value | gitExitCode value == ExitFailure 2 && BS.null (gitStdout value) -> Right False
        Right value -> Left (RefCommandFailure value)

nodeRefArguments :: NodeRefScope -> [String]
nodeRefArguments scope =
    ["for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)" ++ if scope == LocalAndRemoteUpstreams then "%00%(upstream)%00%(upstream:remotename)" else "", "refs/heads/"]
        ++ ["refs/remotes/" | scope /= LocalNodes]

-- Keep independently valid rows, but quarantine every occurrence of a duplicate
-- ref, including a valid row conflicting with a malformed row. Never pick a tip.
decodeNodeRefs :: ObjectFormat -> NodeRefScope -> BS.ByteString -> RefObservation
decodeNodeRefs format scope bytes = RefObservation records errors
  where
    (framed, trailing) = case BS.unsnoc bytes of
        Nothing -> ([], [])
        Just (_, 10) -> (BSC.lines bytes, [])
        _ -> let (prefix, suffix) = BSC.breakEnd (== '\n') bytes in (BSC.lines prefix, [MalformedRefOutput suffix])
    names = Map.fromListWith (+) [(name, 1 :: Int) | row <- BSC.lines bytes, let name = BS.takeWhile (/= 0) row, Just _ <- [classify name]]
    duplicate name = Map.findWithDefault 0 name names > 1
    decoded = map decode framed
    records = [record | Right (Just record) <- decoded, not (duplicate (observedRef record))]
    errors = [problem | Left problem <- decoded] ++ [DuplicateNodeRef name | (name, count) <- Map.toAscList names, count > 1] ++ trailing
    decode row = case BS.split 0 row of
        [name, oid, symbolic] | scope /= LocalAndRemoteUpstreams -> entry row name oid symbolic Nothing Nothing
        [name, oid, symbolic, upstream, remote] | scope == LocalAndRemoteUpstreams -> entry row name oid symbolic (optional upstream) (optional remote)
        _ -> Left (MalformedRefOutput row)
    optional value = if BS.null value then Nothing else Just value
    entry row name oid symbolic upstream effectiveRemote = case classify name of
        Nothing -> Right Nothing
        Just (node, remote) -> do
            object <- either (Left . InvalidRefObject row) Right (parseObjectId format oid)
            Right (Just (NodeRefObservation name node object symbolic remote upstream effectiveRemote))
    classify name = case localNode name of
        Just node -> Just (node, Nothing)
        Nothing | scope /= LocalNodes -> do
            (prefix, node) <- remoteNodeCandidate name
            Just (node, Just prefix)
        Nothing -> Nothing

-- Warnings may describe omitted refs: preserve valid rows, mark incomplete.
-- A failed process/transport provides no reliable complete-record guarantee;
-- its stdout is not salvaged. No history, discovery or network work is hidden.
readNodeRefs :: Git IO -> FilePath -> [(String, Maybe String)] -> ObjectFormat -> NodeRefScope -> IO RefObservation
readNodeRefs git directory environment format scope = do
    outcome <- runGit git (GitInvocation directory ("--no-replace-objects" : nodeRefArguments scope) BS.empty environment)
    pure $ case outcome of
        Left problem -> RefObservation [] [RefTransportFailure problem]
        Right result
            | gitExitCode result /= ExitSuccess -> RefObservation [] [RefCommandFailure result]
            | otherwise ->
                let parsed = decodeNodeRefs format scope (gitStdout result)
                 in parsed{observationErrors = [RefCommandFailure result | not (BS.null (gitStderr result))] ++ observationErrors parsed}

-- Keep configured values separately from Git's resolved upstream atom. Missing
-- refs and duplicate/incomplete configuration must not look like no upstream.
data UpstreamConfig = UpstreamConfig
    { upstreamRemotes :: [BS.ByteString]
    , upstreamSources :: [BS.ByteString]
    }
    deriving (Eq, Show)

data UpstreamConfigProblem = UpstreamConfigProblem
    { configProblemNode :: Maybe NodeId
    , configProblemMessage :: String
    }
    deriving (Eq, Show)

data UpstreamConfigObservation = UpstreamConfigObservation
    { observedConfigs :: Map.Map NodeId UpstreamConfig
    , configProblems :: [UpstreamConfigProblem]
    }
    deriving (Eq, Show)

-- A NUL-terminated key without LF is Git's native valueless representation.
-- Keep other Nodes' records, and taint this Node rather than inventing absence.
-- A lost record boundary or failed process is still a global read failure.
decodeUpstreamConfig :: BS.ByteString -> UpstreamConfigObservation
decodeUpstreamConfig bytes
    | BS.null bytes = UpstreamConfigObservation Map.empty []
    | Just (body, 0) <- BS.unsnoc bytes =
        let decoded = map decode (BS.split 0 body)
         in UpstreamConfigObservation
                (Map.fromListWith combine [pair | (Just pair, _) <- decoded])
                (concatMap snd decoded)
    | otherwise = unavailable "Invalid upstream configuration framing"
  where
    unavailable message = UpstreamConfigObservation Map.empty [UpstreamConfigProblem Nothing message]
    decode record =
        let (key, rest) = BSC.break (== '\n') record
            missingValue = BS.null rest
         in case BS.stripPrefix "branch." key of
                Just suffix -> case BSC.breakEnd (== '.') suffix of
                    (prefix, field) | Just (uuid, 46) <- BS.unsnoc prefix -> case parseNodeId uuid of
                        Right node
                            | field `elem` ["remote", "merge"] ->
                                let value = if missingValue then [] else [BS.tail rest]
                                    config = if field == "remote" then UpstreamConfig value [] else UpstreamConfig [] value
                                 in (Just (node, config), [UpstreamConfigProblem (Just node) ("Missing value for " ++ show key) | missingValue])
                        Left _ -> (Nothing, [])
                        _ -> (Nothing, [UpstreamConfigProblem (either (const Nothing) Just (parseNodeId uuid)) ("Invalid upstream configuration key: " ++ show key)])
                    _ -> (Nothing, [UpstreamConfigProblem Nothing ("Invalid upstream configuration key: " ++ show key)])
                _ -> (Nothing, [UpstreamConfigProblem Nothing ("Invalid upstream configuration entry: " ++ show record)])
    -- Preserve Git's config traversal order for scalar last-value precedence.
    combine (UpstreamConfig a b) (UpstreamConfig c d) = UpstreamConfig (c ++ a) (d ++ b)

readUpstreamConfig :: Git IO -> FilePath -> [(String, Maybe String)] -> IO UpstreamConfigObservation
readUpstreamConfig git directory environment = do
    let args = ["config", "--null", "--get-regexp", "^branch\\.[0-9a-f-]+\\.(remote|merge)$"]
        unavailable message = UpstreamConfigObservation Map.empty [UpstreamConfigProblem Nothing message]
    outcome <- runGit git (GitInvocation directory args BS.empty environment)
    pure $ case outcome of
        Left problem -> unavailable (show problem)
        Right result
            | gitExitCode result == ExitFailure 1 && BS.null (gitStdout result) && BS.null (gitStderr result) -> UpstreamConfigObservation Map.empty []
            | gitExitCode result /= ExitSuccess || not (BS.null (gitStderr result)) -> unavailable (show (gitExitCode result) ++ ": " ++ show (gitStderr result))
            | otherwise -> decodeUpstreamConfig (gitStdout result)
