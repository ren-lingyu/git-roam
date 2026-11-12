{-# LANGUAGE OverloadedStrings #-}

{- | Render CLI results and diagnostics through shared text, JSON and CBOR output.
Preserve filesystem path bytes independently of the selected presentation format.
-}
module GitRoam.Output (OutputFormat (..), Value (..), encodeValue, diagnostic, renderDiagnostic, evidenceValue, renderCreation, renderDelete, decimal, nodeText, oidText, checkValue, renderCheck, renderStatus, statusValue, statusDiagnosticValue, nodeValue, oidValue, worktreePairs, deleteValue, deleteFields) where

import qualified Codec.CBOR.Encoding as CBOR
import qualified Codec.CBOR.Write as CBOR
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Encoding
import qualified GitRoam.Application.Check as Check
import GitRoam.Application.Create (CreationResult (..), createdBundlePath)
import qualified GitRoam.Application.Delete as Deletion
import GitRoam.Application.Protection (ProtectionState (..))
import qualified GitRoam.Application.Status as Status
import GitRoam.Diagnostic (Evidence (..))
import qualified GitRoam.Diagnostic as Diagnostic
import qualified GitRoam.Git.Commit as Commit
import qualified GitRoam.Git.Status as Working
import qualified GitRoam.Git.Worktrees as Worktrees
import GitRoam.ObjectId (ObjectId, objectIdBytes)
import GitRoam.Protocol.Identity (NodeId, nodeIdBytes)
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
data Value = Object [(Text, Value)] | Array [Value] | String Text | Bytes BS.ByteString | Number Integer | Boolean Bool | Null
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
    Number number -> CBOR.encodeInteger number
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

statusDiagnosticValue :: Status.StatusDiagnostic -> Value
statusDiagnosticValue value =
    Object
        [ ("code", String (Status.statusCode value))
        , ("severity", String "error")
        , ("message", String (Status.statusMessage value))
        ,
            ( "context"
            , Object
                ( [("node", nodeValue node) | Just node <- [Status.diagnosticNode value]]
                    ++ [("property", String (Status.propertyName property)) | Just property <- [Status.diagnosticProperty value]]
                    ++ [("path", Bytes path) | Just path <- [Status.diagnosticPath value]]
                )
            )
        ]

protectionText :: ProtectionState -> Text
protectionText ProtectionEnabled = "enabled"
protectionText ProtectionDisabled = "disabled"
protectionText ProtectionMisconfigured = "misconfigured"
protectionText ProtectionUnavailable = "unavailable"

statusValue :: Status.StatusReport -> Value
statusValue report = case report of
    Status.RepositoryReport state issues -> Object [("repository", Object [("protection", Object [("state", String (protectionText state))])]), ("diagnostics", diagnostics issues)]
    Status.NodesReport rows issues -> Object [("nodes", Array (map row rows)), ("diagnostics", diagnostics issues)]
  where
    diagnostics = Array . map statusDiagnosticValue
    property _ _ Status.NotRequested = []
    property name _ Status.Unavailable = [(name, Null)]
    property name encode (Status.Available value) = [(name, encode value)]
    row node =
        Object $
            [("node", nodeValue (Status.statusNode node))]
                ++ property "tip" oidValue (Status.statusTip node)
                ++ property "commit" commit (Status.statusCommit node)
                ++ property "worktrees" (Array . map tree) (Status.statusWorktrees node)
                ++ property "status" (Array . map working) (Status.statusWorkingTrees node)
                ++ property "remote" remote (Status.statusRemote node)
    commit value =
        Object
            [ ("tree", oidValue (Commit.metadataTree value))
            , ("parents", Array (map oidValue (Commit.metadataParents value)))
            , ("author", identity (Commit.metadataAuthor value))
            , ("committer", identity (Commit.metadataCommitter value))
            , ("subject", Bytes (Commit.metadataSubject value))
            , ("message", Bytes (Commit.metadataMessage value))
            ]
    identity value = Object [("name", Bytes (Commit.identityName value)), ("email", Bytes (Commit.identityEmail value)), ("date", date (Commit.identityDate value))]
    date value = Object [("timestamp", Number (Commit.dateTimestamp value)), ("offset", String (Encoding.decodeUtf8 (Commit.dateOffset value)))]
    tree value =
        Object
            [ ("path", Bytes (Worktrees.treePath value))
            , ("head", maybe Null oidValue (Worktrees.treeHead value))
            , ("branch", maybe Null Bytes (Worktrees.treeBranch value))
            , ("main", Boolean (Worktrees.treeMain value))
            , ("bare", Boolean (Worktrees.treeBare value))
            , ("detached", Boolean (Worktrees.treeDetached value))
            , ("locked", Boolean (Worktrees.treeLocked value /= Nothing))
            , ("lock_reason", maybe Null Bytes (Worktrees.treeLocked value))
            , ("prunable", Boolean (Worktrees.treePrunable value /= Nothing))
            , ("prune_reason", maybe Null Bytes (Worktrees.treePrunable value))
            ]
    working value =
        Object
            [ ("path", Bytes (Status.statusWorktreePath value))
            , ("state", String (case Status.statusWorktreeSummary value of Nothing -> "unavailable"; Just summary -> if Working.workingTreeDirty summary then "dirty" else "clean"))
            , ("staged", maybe Null (Boolean . Working.workingStaged) (Status.statusWorktreeSummary value))
            , ("unstaged", maybe Null (Boolean . Working.workingUnstaged) (Status.statusWorktreeSummary value))
            , ("untracked", maybe Null (Boolean . Working.workingUntracked) (Status.statusWorktreeSummary value))
            , ("unmerged", maybe Null (Boolean . Working.workingUnmerged) (Status.statusWorktreeSummary value))
            ]
    remote value = Object [("upstream", case Status.remoteUpstream value of Status.Available result -> maybe Null upstream result; _ -> Null), ("refs", maybe Null (Array . map (\(ref, tip) -> Object [("ref", Bytes ref), ("tip", oidValue tip)])) (Status.remoteRefs value))]
    upstream value = Object [("remote", maybe Null Bytes (Status.upstreamRemote value)), ("source", maybe Null Bytes (Status.upstreamSource value)), ("ref", maybe Null Bytes (Status.upstreamRef value))]

renderStatus :: Status.StatusReport -> Text
renderStatus report = case report of
    Status.RepositoryReport state _ -> "protection " <> protectionText state <> "\n"
    Status.NodesReport [] _ -> "No local Nodes observed.\n"
    Status.NodesReport rows _ -> Text.concat (map row rows)
  where
    field _ _ Status.NotRequested = []
    field name _ Status.Unavailable = ["  " <> name <> " unavailable"]
    field name render (Status.Available value) = map ("  " <>) (render name value)
    row value =
        Text.unlines $
            ["node " <> nodeText (Status.statusNode value)]
                ++ field "tip" (\name oid -> [name <> " " <> oidText oid]) (Status.statusTip value)
                ++ field "commit" renderCommit (Status.statusCommit value)
                ++ field "worktrees" renderTrees (Status.statusWorktrees value)
                ++ field "status" renderWorking (Status.statusWorkingTrees value)
                ++ field "remote" renderRemote (Status.statusRemote value)
    raw = maybe "unavailable" (Text.pack . show)
    renderCommit name value =
        [name, "  tree " <> oidText (Commit.metadataTree value)]
            ++ ["  parent " <> oidText parent | parent <- Commit.metadataParents value]
            ++ ["  author " <> renderIdentity (Commit.metadataAuthor value), "  committer " <> renderIdentity (Commit.metadataCommitter value), "  subject " <> Text.pack (show (Commit.metadataSubject value)), "  message " <> Text.pack (show (Commit.metadataMessage value))]
    renderIdentity value = Text.pack (show (Commit.identityName value)) <> " <" <> Text.pack (show (Commit.identityEmail value)) <> "> " <> Text.pack (show (Commit.dateTimestamp (Commit.identityDate value))) <> " " <> Encoding.decodeUtf8 (Commit.dateOffset (Commit.identityDate value))
    flag True = "yes"
    flag False = "no"
    renderWorking name [] = [name <> " none"]
    renderWorking _ values =
        concatMap
            ( \value ->
                ("status " <> Text.pack (show (Status.statusWorktreePath value))) : case Status.statusWorktreeSummary value of
                    Nothing -> ["  unavailable"]
                    Just summary -> ["  " <> (if Working.workingTreeDirty summary then "dirty" else "clean") <> " staged " <> flag (Working.workingStaged summary) <> " unstaged " <> flag (Working.workingUnstaged summary) <> " untracked " <> flag (Working.workingUntracked summary) <> " unmerged " <> flag (Working.workingUnmerged summary)]
            )
            values
    renderTrees name [] = [name <> " none"]
    renderTrees _ trees = concatMap renderTree trees
    renderTree tree =
        [ "worktree " <> Text.pack (show (Worktrees.treePath tree))
        , "  head " <> maybe "unavailable" oidText (Worktrees.treeHead tree)
        , "  branch " <> raw (Worktrees.treeBranch tree)
        , "  main " <> flag (Worktrees.treeMain tree) <> " bare " <> flag (Worktrees.treeBare tree) <> " detached " <> flag (Worktrees.treeDetached tree)
        , "  locked " <> flag (Worktrees.treeLocked tree /= Nothing) <> " prunable " <> flag (Worktrees.treePrunable tree /= Nothing)
        ]
            ++ ["  lock-reason " <> Text.pack (show reason) | Just reason <- [Worktrees.treeLocked tree]]
            ++ ["  prune-reason " <> Text.pack (show reason) | Just reason <- [Worktrees.treePrunable tree]]
    renderRemote name remote =
        [name]
            ++ ( case Status.remoteUpstream remote of
                    Status.Available Nothing -> ["  upstream none"]
                    Status.Available (Just upstream) -> ["  upstream remote " <> raw (Status.upstreamRemote upstream), "    source " <> raw (Status.upstreamSource upstream), "    ref " <> raw (Status.upstreamRef upstream)]
                    _ -> ["  upstream unavailable"]
               )
            ++ tracking remote
    tracking remote = case Status.remoteRefs remote of
        Nothing -> ["  refs unavailable"]
        Just [] -> ["  refs none"]
        Just refs -> ["  ref " <> Text.pack (show ref) <> " " <> oidText tip | (ref, tip) <- refs]

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

checkValue :: Bool -> Check.CheckReport -> Value
checkValue showRefs report =
    Object $
        [("valid", case Check.checkConclusion report of Check.Valid -> Boolean True; Check.Invalid -> Boolean False; Check.Inconclusive -> Null)]
            ++ [("refs", maybe Null (Object . map (\(node, oid) -> ("refs/heads/" <> nodeText node, oidValue oid)) . Map.toAscList) (Check.checkRefs report)) | showRefs]
            ++ [("diagnostics", Array (map checkDiagnosticValue (Check.checkDiagnostics report)))]

checkDiagnosticValue :: Check.CheckDiagnostic -> Value
checkDiagnosticValue value =
    Object $
        [("code", String (Check.checkCode value)), ("severity", String "error"), ("message", String (Check.checkMessage value))]
            ++ [("context", Object context) | not (null context)]
  where
    context =
        [("node", nodeValue node) | Just node <- [Check.checkNode value]]
            ++ [("object", oidValue oid) | Just oid <- [Check.checkObject value]]

renderCheck :: Bool -> Check.CheckReport -> Text
renderCheck showRefs report =
    Text.unlines $
        [case Check.checkConclusion report of Check.Valid -> "valid"; Check.Invalid -> "invalid"; Check.Inconclusive -> "inconclusive"]
            ++ (if showRefs then maybe ["refs unavailable"] refs (Check.checkRefs report) else [])
            ++ [Check.checkCode issue <> ": " <> Check.checkMessage issue | issue <- Check.checkDiagnostics report]
  where
    refs values | Map.null values = ["refs (empty)"]
    refs values = ["ref refs/heads/" <> nodeText node <> " " <> oidText oid | (node, oid) <- Map.toAscList values]
