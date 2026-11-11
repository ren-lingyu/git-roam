{-# LANGUAGE OverloadedStrings #-}

{- | Render creation results without imposing a text encoding on filesystem paths.
The format is a presentation decision; Node creation itself is format-agnostic.
-}
module GitRoam.Output (OutputFormat (..), Value (..), encodeValue, diagnostic, renderDiagnostic, evidenceValue, renderCreation, renderDelete, decimal, nodeText, oidText, stateDiagnostic, inspectionDiagnostic, renderStatus, nodeValue, oidValue, worktreePairs, deleteValue, deleteFields, inspectionValue, inspectionCode, inspectionHasReport) where

import qualified Codec.CBOR.Encoding as CBOR
import qualified Codec.CBOR.Write as CBOR
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import GitRoam.Application.Create (CreationResult (..), createdBundlePath)
import qualified GitRoam.Application.Delete as Deletion
import GitRoam.Application.Inspect
import GitRoam.Diagnostic (Evidence (..))
import qualified GitRoam.Diagnostic as Diagnostic
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId (ObjectId, objectIdBytes)
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity (NodeId, nodeIdBytes)
import GitRoam.Protocol.Objects (ObjectProblem (..))
import GitRoam.Protocol.Repository
import GitRoam.Worktree.Paths (encodePath)

data OutputFormat = TextFormat | JsonFormat | CborFormat
    deriving (Eq, Show)

{- | The text encoding is intentionally unchanged for existing CLI consumers.
JSON adds a readable UTF-8 view and an authoritative Base64 byte view.
CBOR uses byte strings directly, so no Unicode conversion is needed.
-}
renderCreation :: OutputFormat -> CreationResult -> IO BS.ByteString
renderCreation format result = case format of
    TextFormat ->
        pure $
            Encoding.encodeUtf8 $
                Text.unlines
                    [ "node " <> identity
                    , "root " <> root
                    , "worktree " <> Text.pack (show (createdPath result))
                    , "bundle " <> Text.pack (show (createdBundlePath result))
                    ]
    _ -> do
        (worktree, bundle) <- pathBytes
        pure $
            encodeValue format $
                Object
                    [("node", String identity), ("root", String root), ("worktree", Bytes worktree), ("bundle", Bytes bundle)]
  where
    identity = Encoding.decodeUtf8 (nodeIdBytes (createdNode result))
    root = Encoding.decodeUtf8 (objectIdBytes (createdRoot result))
    pathBytes = (,) <$> encodePath (createdPath result) <*> encodePath (createdBundlePath result)

-- | Path bytes are the source of truth; UTF-8 is only a convenience field.
jsonPath :: BS.ByteString -> Aeson.Value
jsonPath bytes =
    Aeson.object
        [ "utf8" Aeson..= (either (const Nothing) Just (Encoding.decodeUtf8' bytes) :: Maybe Text)
        , "base64" Aeson..= Encoding.decodeUtf8 (Base64.encode bytes)
        ]

-- One logical model shared by both wire encodings. Bytes never pass through text.
data Value = Object [(Text, Value)] | Array [Value] | String Text | Bytes BS.ByteString | Number Int | Boolean Bool | Null
    deriving (Eq, Show)

encodeValue :: OutputFormat -> Value -> BS.ByteString
encodeValue CborFormat = CBOR.toStrictByteString . cborValue
encodeValue _ = (<> "\n") . BL.toStrict . Aeson.encode . jsonValue

jsonValue :: Value -> Aeson.Value
jsonValue value = case value of
    Object fields -> Aeson.object [Key.fromText key Aeson..= jsonValue item | (key, item) <- fields]
    Array values -> Aeson.toJSON (map jsonValue values)
    String text -> Aeson.toJSON text
    Bytes bytes -> jsonPath bytes
    Number number -> Aeson.toJSON number
    Boolean flag -> Aeson.toJSON flag
    Null -> Aeson.Null

cborValue :: Value -> CBOR.Encoding
cborValue value = case value of
    Object fields -> CBOR.encodeMapLen (fromIntegral (length fields)) <> foldMap (\(key, item) -> CBOR.encodeString key <> cborValue item) fields
    Array values -> CBOR.encodeListLen (fromIntegral (length values)) <> foldMap cborValue values
    String text -> CBOR.encodeString text
    Bytes bytes -> CBOR.encodeBytes bytes
    Number number -> CBOR.encodeInt number
    Boolean flag -> CBOR.encodeBool flag
    Null -> CBOR.encodeNull

diagnostic :: Text -> Text -> Text -> Value
diagnostic code severity message = renderDiagnostic (Diagnostic.Diagnostic code (if severity == "warning" then Diagnostic.Warning else Diagnostic.Error) message)

renderDiagnostic :: Diagnostic.Diagnostic -> Value
renderDiagnostic value = Object [("code", String (Diagnostic.diagnosticCode value)), ("severity", String (case Diagnostic.diagnosticSeverity value of Diagnostic.Error -> "error"; Diagnostic.Warning -> "warning")), ("message", String (Diagnostic.diagnosticMessage value))]

evidenceValue :: Evidence -> Value
evidenceValue value =
    Object
        [ ("node", maybe Null (String . Encoding.decodeUtf8 . nodeIdBytes) (evidenceNode value))
        , ("candidate", maybe Null (String . Encoding.decodeUtf8 . objectIdBytes) (evidenceCandidate value))
        , ("ref_update_confirmed", maybe Null Boolean (evidenceRefConfirmed value))
        , ("operation_attempted", maybe Null Boolean (evidenceAttempted value))
        , ("removed_worktrees", Array [Object [("node", String (Encoding.decodeUtf8 (nodeIdBytes node))), ("path", Bytes path)] | (node, path) <- evidenceRemoved value])
        , ("remaining_worktrees", maybe Null (Array . map (\tree -> Object [("path", Bytes (Worktrees.treePath tree)), ("node", maybe Null (String . Encoding.decodeUtf8 . nodeIdBytes) (Worktrees.worktreeNode tree)), ("main", Boolean (Worktrees.treeMain tree)), ("locked", maybe Null Bytes (Worktrees.treeLocked tree)), ("prunable", maybe Null Bytes (Worktrees.treePrunable tree))])) (evidenceRemainingWorktrees value))
        , ("actual_refs", maybe Null (Array . map (\(node, oid) -> Object [("node", String (Encoding.decodeUtf8 (nodeIdBytes node))), ("oid", String (Encoding.decodeUtf8 (objectIdBytes oid)))])) (evidenceActualRefs value))
        , ("remaining_config_keys", maybe Null (Array . map Bytes) (evidenceRemainingConfig value))
        ]

renderDelete :: Deletion.DeletePreview -> Text
renderDelete report =
    Text.unlines $
        [ "Read-only Node deletion preview; no changes were made."
        , "node " <> node (Deletion.deleteNode report)
        , "old " <> oid (Deletion.deleteOldTip report)
        , "root " <> oid (Deletion.deleteRoot report)
        ]
            ++ ["plan " <> Text.pack (BSC.unpack identifier) | Just identifier <- [Deletion.deletePlanId report]]
            ++ ["exclusive commit " <> oid value | value <- Set.toList (Deletion.deleteExclusiveCommits report)]
            ++ ["checked out " <> Text.pack (show (Worktrees.treePath record)) <> if Worktrees.treeMain record then " (main)" else " (linked)" | record <- Deletion.deleteWorktrees report]
            ++ ["remove local config " <> Text.pack (BSC.unpack key) | key <- Deletion.deleteConfigKeys report]
            ++ ["blocked " <> Text.pack problem | problem <- Deletion.deleteProblems report]
            ++ ["Exclusive commits are not erased; they are unreachable from the remaining managed refs at this observation.", "No cascading removal, object erasure or recovery guarantee. Remote refs remain; deploy may recreate this Node."]
  where
    node = Text.pack . BSC.unpack . nodeIdBytes
    oid = Text.pack . BSC.unpack . objectIdBytes

decimal :: Int -> Text
decimal = Text.pack . show

nodeText :: NodeId -> Text
nodeText = Text.pack . BSC.unpack . nodeIdBytes

oidText :: ObjectId -> Text
oidText = Text.pack . BSC.unpack . objectIdBytes

stateDiagnostic :: StateProblem -> Text
stateDiagnostic issue = case issue of
    UnknownNodeTip node tip -> "history-unavailable: " <> nodeText node <> " points to unknown " <> oidText tip
    RefIdentityMismatch node actual tip -> "identity-mismatch: branch " <> nodeText node <> " points to Node " <> nodeText actual <> " at " <> oidText tip

inspectionDiagnostic :: InspectionError -> Text
inspectionDiagnostic problem = case problem of
    HistoryFailure (ObjectUnavailable oid (WrongObjectType kind)) -> "object-type-mismatch: " <> oidText oid <> " has type " <> Text.pack (show kind)
    ReferencesChanged -> "observation-changed: Node refs changed during inspection; run the command again."
    ShallowRepository -> "history-incomplete: shallow repositories cannot establish complete Node history."
    MissingReachableObjects objects -> "objects-missing: " <> Text.intercalate ", " (map (Text.pack . BSC.unpack) objects)
    NodeNotManaged node -> "node-not-managed: no local branch for " <> nodeText node
    SymbolicNodeBranch node target -> "symbolic-node-branch: " <> nodeText node <> " points to " <> Text.pack (show target)
    HistoryFailure (ObjectUnavailable oid reason) -> "history-unavailable: " <> oidText oid <> " " <> Text.pack (show reason)
    HistoryFailure reason -> "history-invalid: " <> Text.pack (show reason)
    _ -> "git-read-failure: " <> Text.pack (show problem)

renderStatus :: InspectionReport -> Text
renderStatus report
    | null (reportNodes report) = "No managed Nodes.\n"
    | otherwise = Text.concat (map renderNode (reportNodes report))
  where
    renderNode node =
        Text.unlines $
            [ "node " <> nodeText (viewNode node)
            , "  tip " <> oidText (viewTip node) <> " (" <> kind (viewKind node) <> ")"
            , "  checkpoint " <> maybe "none" oidText (viewLatestCheckpoint node)
            , "  content-tail " <> (case viewKind node of Content _ -> "yes"; _ -> "no")
            , "  checkpoints " <> decimal (viewCheckpointCount node)
            , "  contexts " <> (if null (viewContextParents node) then "none" else "")
            ]
                ++ ["    " <> oidText oid | oid <- viewContextParents node]
                ++ [ "  worktree " <> Text.pack (show (worktreePath worktree)) <> if worktreeIsMain worktree then " (main; not a removable deployment)" else " (linked)"
                   | worktree <- reportWorktrees report
                   , worktreeNode worktree == Just (viewNode node)
                   ]
    kind Root = "root"
    kind (Content _) = "content"
    kind (Checkpoint _ _) = "checkpoint"

nodeValue :: NodeId -> Value
nodeValue = String . nodeText

oidValue :: ObjectId -> Value
oidValue = String . oidText

worktreePairs :: [(NodeId, BS.ByteString)] -> Value
worktreePairs pairs = Array [Object [("node", nodeValue node), ("path", Bytes path)] | (node, path) <- pairs]

deleteValue :: Deletion.DeletePreview -> Value
deleteValue = Object . deleteFields

deleteFields :: Deletion.DeletePreview -> [(Text, Value)]
deleteFields report =
    [("node", nodeValue (Deletion.deleteNode report)), ("old_tip", oidValue (Deletion.deleteOldTip report)), ("root", oidValue (Deletion.deleteRoot report)), ("exclusive_commits", Array (map oidValue (Set.toList (Deletion.deleteExclusiveCommits report)))), ("worktrees", Array [Object [("path", Bytes (Worktrees.treePath tree)), ("main", Boolean (Worktrees.treeMain tree))] | tree <- Deletion.deleteWorktrees report]), ("config_keys", Array (map Bytes (Deletion.deleteConfigKeys report))), ("plan_id", maybe Null (String . Encoding.decodeUtf8) (Deletion.deletePlanId report)), ("diagnostics", Array [diagnostic "node_checked_out" "error" (Text.pack problem) | problem <- Deletion.deleteProblems report])]

inspectionValue :: InspectionReport -> Value
inspectionValue report = Object [("valid", Boolean (null (reportProblems report))), ("nodes", Array (map view (reportNodes report))), ("diagnostics", Array [diagnostic (case problem of UnknownNodeTip _ _ -> "history_unavailable"; RefIdentityMismatch _ _ _ -> "identity_mismatch") "error" (stateDiagnostic problem) | problem <- reportProblems report])]
  where
    view node = Object [("node", nodeValue (viewNode node)), ("tip", oidValue (viewTip node)), ("kind", String (case viewKind node of Root -> "root"; Content _ -> "content"; Checkpoint _ _ -> "checkpoint")), ("latest_checkpoint", maybe Null oidValue (viewLatestCheckpoint node)), ("contexts", Array (map oidValue (viewContextParents node))), ("checkpoint_count", Number (viewCheckpointCount node)), ("content_tail", Boolean (case viewKind node of Content _ -> True; _ -> False)), ("worktrees", Array [Object [("path", Bytes (worktreePath tree)), ("main", Boolean (worktreeIsMain tree))] | tree <- reportWorktrees report, worktreeNode tree == Just (viewNode node)])]

inspectionCode :: InspectionError -> Text
inspectionCode problem = case problem of
    RepositoryDiscoveryFailure _ -> "repository_discovery_failed"
    InspectionGitFailure _ _ -> "git_read_failed"
    InspectionTransportFailure _ _ -> "git_transport_failed"
    InvalidGitOutput _ _ -> "invalid_git_output"
    SymbolicNodeBranch _ _ -> "symbolic_node_branch"
    NodeNotManaged _ -> "node_not_managed"
    ShallowRepository -> "history_incomplete"
    HistoryFailure _ -> "history_invalid"
    MissingReachableObjects _ -> "objects_missing"
    ReferencesChanged -> "observation_changed"
    CandidateStateInvalid _ -> "candidate_state_invalid"

inspectionHasReport :: InspectionError -> Bool
inspectionHasReport problem = case problem of
    RepositoryDiscoveryFailure _ -> False
    InspectionGitFailure _ _ -> False
    InspectionTransportFailure _ _ -> False
    InvalidGitOutput _ _ -> False
    _ -> True
