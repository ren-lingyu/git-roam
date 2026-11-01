{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import Control.Monad.Trans.State.Strict (State, get, modify', put, runState)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import Data.Functor.Identity (Identity (..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import GitRoam.ObjectId
import GitRoam.Protocol.History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import Numeric (showHex)
import TestSupport

data Fixture = Fixture
    { nextId :: Int
    , fixtureFormat :: ObjectFormat
    , fixtureCommits :: Map ObjectId CommitObject
    , fixtureTrees :: Map ObjectId [TreeEntry]
    }

type Build = State Fixture

build :: ObjectFormat -> Build a -> (a, Fixture)
build format action = runState action (Fixture 1 format Map.empty Map.empty)

fresh :: Build ObjectId
fresh = do
    fixture <- get
    let digits = showHex (nextId fixture) ""
        bytes = BSC.pack (replicate (objectIdLength (fixtureFormat fixture) - length digits) '0' ++ digits)
    put fixture{nextId = nextId fixture + 1}
    either error pure (parseObjectId (fixtureFormat fixture) bytes)

tree :: [TreeEntry] -> Build ObjectId
tree entries = do
    oid <- fresh
    modify' (\fixture -> fixture{fixtureTrees = Map.insert oid entries (fixtureTrees fixture)})
    pure oid

commit :: ObjectId -> [ObjectId] -> Build ObjectId
commit content parents = do
    oid <- fresh
    modify' (\fixture -> fixture{fixtureCommits = Map.insert oid (CommitObject content parents) (fixtureCommits fixture)})
    pure oid

uuidA, uuidB, uuidC :: BS.ByteString
uuidA = "11111111-1111-4111-8111-111111111111"
uuidB = "22222222-2222-4222-8222-222222222222"
uuidC = "33333333-3333-4333-8333-333333333333"

nodeTree :: BS.ByteString -> Bool -> Build ObjectId
nodeTree uuid payload = do
    marker <- fresh
    directory <-
        tree $
            [TreeEntry ".roam" RegularFile marker]
                ++ [TreeEntry "note.org" RegularFile marker | payload]
    tree [TreeEntry uuid Directory directory]

root :: BS.ByteString -> Build (ObjectId, ObjectId)
root uuid = do
    content <- nodeTree uuid False
    oid <- commit content []
    pure (oid, content)

checkpoint :: ObjectId -> ObjectId -> [ObjectId] -> Build (ObjectId, ObjectId)
checkpoint content base extra = do
    editing <- commit content [base]
    formal <- commit content (base : editing : extra)
    pure (editing, formal)

source :: Fixture -> HistorySource Identity
source fixture =
    HistorySource
        (\oid -> pure (maybe (Left MissingObject) Right (Map.lookup oid (fixtureCommits fixture))))
        (\oid -> pure (maybe (Left MissingObject) Right (Map.lookup oid (fixtureTrees fixture))))

validate :: Fixture -> [ObjectId] -> Either HistoryError ValidatedHistory
validate fixture tips = runIdentity (validateHistory (fixtureFormat fixture) (source fixture) tips)

invalid :: (HistoryError -> Bool) -> Fixture -> [ObjectId] -> IO ()
invalid matches fixture tips = case validate fixture tips of
    Left problem -> assertTrue ("Unexpected protocol error: " ++ show problem) (matches problem)
    Right _ -> ioError (userError "Accepted invalid history")

projection :: ValidatedHistory -> ObjectId -> IO FormalVersion
projection history oid = do
    value <- expectRight (projectCheckpoint history oid)
    maybe (ioError (userError "Expected formal projection")) pure value

main :: IO ()
main =
    runTests $
        [ ("canonical UUID labels", uuidTest)
        , ("invalid UUID labels", invalidUuidTest)
        , ("tree identity and marker constraints", identityTreeTest)
        , ("Root contains no payload", rootPayloadTest)
        , ("marker blob content has no protocol meaning", markerContentTest)
        , ("Content cannot change identity", identityChangeTest)
        , ("ordinary Content may fork and have an empty diff", contentForkTest)
        , ("Content has no formal projection", contentProjectionTest)
        , ("Checkpoint keeps complete editing chain and exact tree", editingChainTest)
        , ("Checkpoint first parent must be Root or Checkpoint", mainParentTest)
        , ("Checkpoint second parent must be Content", secondParentTest)
        , ("Checkpoint main and Content parents must have the same identity", parentIdentityTest)
        , ("Content chain must return to the first parent", contentBaseTest)
        , ("Checkpoint cannot change its Content tree", checkpointTreeTest)
        , ("extra parents must be Checkpoints", extraParentTest)
        , ("Checkpoint parents must be distinct", duplicateParentsTest)
        , ("one direct version per external UUID", duplicateDependencyTest)
        , ("same UUID must have one Root across all input histories", rootConflictTest)
        , ("same UUID merge parent cannot change Root", mergeRootConflictTest)
        , ("extra parent order has no formal semantics", parentOrderTest)
        , ("complete dependency declaration does not inherit", completeDependenciesTest)
        , ("direct dependency versions can be replaced", replaceDependencyTest)
        , ("transitive contexts may retain different versions", transitiveVersionsTest)
        , ("new same-tree Content supports dependency-only Checkpoints", emptyContentTest)
        , ("old second parent cannot be reused", reusedContentTest)
        , ("same-Node merged formal histories are retained", mergeHistoryTest)
        , ("cross-Node Git ancestry does not imply formal ancestry", ancestryTrapTest)
        , ("missing commit evidence is not a Root", missingCommitTest)
        , ("missing tree evidence is not an empty tree", missingTreeTest)
        , ("incomplete and wrong-type evidence remains explicit", incompleteTest)
        , ("cyclic provider input rejects", cycleTest)
        , ("mixed object formats reject", mixedFormatTest)
        , ("queries reject unknown commits and non-Checkpoints", queryTest)
        , ("shared objects are loaded once per validation", cacheTest)
        ]
            ++ [("generated graph projection properties " ++ show format, graphProperties format) | format <- [Sha1, Sha256]]

uuidTest :: IO ()
uuidTest = forM_ [uuidA, "00000000-0000-0000-0000-000000000000", "abcdef01-2345-1678-9abc-def012345678"] $ \bytes -> do
    node <- expectRight (parseNodeId bytes)
    assertEqual bytes (nodeIdBytes node)

invalidUuidTest :: IO ()
invalidUuidTest =
    mapM_
        (expectLeft . parseNodeId)
        [BS.empty, "ABCDEF01-2345-1678-9abc-def012345678", "11111111111141118111111111111111", uuidA <> "\n", BS.replicate 36 255]

identityTreeTest :: IO ()
identityTreeTest = do
    let (tips, fixture) = build Sha1 $ do
            blob <- fresh
            good <- tree [TreeEntry ".roam" RegularFile blob]
            missing <- tree [TreeEntry "note.org" RegularFile blob]
            symlink <- tree [TreeEntry ".roam" SymbolicLink blob]
            directory <- tree [TreeEntry ".roam" Directory good]
            duplicate <- tree [TreeEntry ".roam" RegularFile blob, TreeEntry ".roam" RegularFile blob]
            malformed <- tree [TreeEntry "a/b" RegularFile blob, TreeEntry ".roam" RegularFile blob]
            mapM
                (\entries -> tree entries >>= \content -> commit content [])
                [ []
                , [TreeEntry uuidA Directory good, TreeEntry "outside" RegularFile blob]
                , [TreeEntry uuidA RegularFile blob]
                , [TreeEntry "not-a-uuid" Directory good]
                , [TreeEntry uuidA Directory missing]
                , [TreeEntry uuidA Directory symlink]
                , [TreeEntry uuidA Directory directory]
                , [TreeEntry uuidA Directory duplicate]
                , [TreeEntry uuidA Directory malformed]
                ]
    forM_ tips $ \tip -> invalid (\e -> case e of InvalidNodeTree _ _ -> True; _ -> False) fixture [tip]

rootPayloadTest :: IO ()
rootPayloadTest = do
    let (tip, fixture) = build Sha1 (nodeTree uuidA True >>= \content -> commit content [])
    invalid (\e -> case e of InvalidNodeTree _ RootContainsContent -> True; _ -> False) fixture [tip]

markerContentTest :: IO ()
markerContentTest = do
    -- The provider deliberately supplies no marker blob body. It is irrelevant.
    let (tip, fixture) = build Sha1 $ do
            blob <- fresh
            directory <- tree [TreeEntry ".roam" ExecutableFile blob]
            content <- tree [TreeEntry uuidA Directory directory]
            commit content []
    history <- expectRight (validate fixture [tip])
    value <- maybe (fail "Missing Root") pure (lookupCommit history tip)
    assertEqual Root (validatedKind value)
    assertEqual tip (validatedRoot value)

identityChangeTest :: IO ()
identityChangeTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, _) <- root uuidA
            content <- nodeTree uuidB False
            commit content [r]
    invalid (\e -> case e of IdentityChanged _ _ _ -> True; _ -> False) fixture [tip]

contentForkTest :: IO ()
contentForkTest = do
    let ((r, a, b), fixture) = build Sha1 $ do
            (builtR, content) <- root uuidA
            builtA <- commit content [builtR]
            builtB <- commit content [builtR]
            pure (builtR, builtA, builtB)
    history <- expectRight (validate fixture [a, b])
    assertEqual (Right Set.empty) (formalHistory history a)
    forM_ [a, b] $ \tip -> do
        value <- maybe (fail "Missing Content") pure (lookupCommit history tip)
        assertEqual (Content r r) (validatedKind value)

contentProjectionTest :: IO ()
contentProjectionTest = do
    let ((r, w, k), fixture) = build Sha1 $ do
            (builtR, content) <- root uuidA
            (builtW, builtK) <- checkpoint content builtR []
            pure (builtR, builtW, builtK)
    history <- expectRight (validate fixture [k])
    assertEqual (Right Nothing) (projectCheckpoint history r)
    assertEqual (Right Nothing) (projectCheckpoint history w)
    formal <- projection history k
    assertEqual Map.empty (versionDependencies formal)
    assertEqual Set.empty (versionHistory formal)

editingChainTest :: IO ()
editingChainTest = do
    let ((r, w1, w3, k, content), fixture) = build Sha256 $ do
            (builtR, _) <- root uuidA
            builtContent <- nodeTree uuidA True
            builtW1 <- commit builtContent [builtR]
            w2 <- commit builtContent [builtW1]
            builtW3 <- commit builtContent [w2]
            builtK <- commit builtContent [builtR, builtW3]
            pure (builtR, builtW1, builtW3, builtK, builtContent)
    history <- expectRight (validate fixture [k])
    formal <- projection history k
    assertEqual content (versionTree formal)
    assertEqual (Right (Set.singleton k)) (formalHistory history k)
    assertTrue "Editing history was lost" (all (\oid -> lookupCommit history oid /= Nothing) [r, w1, w3])

mainParentTest :: IO ()
mainParentTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            w1 <- commit t [r]
            w2 <- commit t [w1]
            commit t [w1, w2]
    invalid (\e -> case e of InvalidMainPredecessor _ _ -> True; _ -> False) fixture [tip]

secondParentTest :: IO ()
secondParentTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, k) <- checkpoint t r []
            commit t [r, k]
    invalid (\e -> case e of InvalidContentTip _ _ -> True; _ -> False) fixture [tip]

parentIdentityTest :: IO ()
parentIdentityTest = forM_ [False, True] $ \foreignMain -> do
    let (tip, fixture) = build Sha1 $ do
            (a, at) <- root uuidA
            (b, bt) <- root uuidB
            w <- commit (if foreignMain then at else bt) [if foreignMain then a else b]
            commit at [if foreignMain then b else a, w]
    invalid (\e -> case e of IdentityChanged _ _ _ -> True; _ -> False) fixture [tip]

contentBaseTest :: IO ()
contentBaseTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, k) <- checkpoint t r []
            w <- commit t [r]
            commit t [k, w]
    invalid (\e -> case e of ContentBaseMismatch _ _ _ -> True; _ -> False) fixture [tip]

checkpointTreeTest :: IO ()
checkpointTreeTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            w <- commit t [r]
            other <- nodeTree uuidA True
            commit other [r, w]
    invalid (\e -> case e of CheckpointTreeMismatch _ _ -> True; _ -> False) fixture [tip]

extraParentTest :: IO ()
extraParentTest = forM_ [False, True] $ \useContent -> do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (b, bt) <- root uuidB
            extra <- if useContent then commit bt [b] else pure b
            snd <$> checkpoint t r [extra]
    invalid (\e -> case e of ExtraParentNotCheckpoint _ _ -> True; _ -> False) fixture [tip]

duplicateParentsTest :: IO ()
duplicateParentsTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            w <- commit t [r]
            commit t [r, w, w]
    invalid (\e -> case e of DuplicateParents _ -> True; _ -> False) fixture [tip]

duplicateDependencyTest :: IO ()
duplicateDependencyTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (b, bt) <- root uuidB
            (_, b1) <- checkpoint bt b []
            (_, b2) <- checkpoint bt b1 []
            snd <$> checkpoint t r [b1, b2]
    invalid (\e -> case e of DuplicateDependency _ _ -> True; _ -> False) fixture [tip]

rootConflictTest :: IO ()
rootConflictTest = do
    let (tips, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            other <- commit t []
            pure [r, other]
    invalid (\e -> case e of ConflictingRoots _ _ _ -> True; _ -> False) fixture tips

mergeRootConflictTest :: IO ()
mergeRootConflictTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            other <- commit t []
            (_, otherK) <- checkpoint t other []
            snd <$> checkpoint t r [otherK]
    invalid (\e -> case e of ConflictingRoots _ _ _ -> True; _ -> False) fixture [tip]

parentOrderTest :: IO ()
parentOrderTest = do
    let ((a, b), fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, side) <- checkpoint t r []
            (br, bt) <- root uuidB
            (_, bk) <- checkpoint bt br []
            (cr, ct) <- root uuidC
            (_, ck) <- checkpoint ct cr []
            w <- commit t [r]
            builtA <- commit t [r, w, side, bk, ck]
            builtB <- commit t [r, w, ck, side, bk]
            pure (builtA, builtB)
    history <- expectRight (validate fixture [a, b])
    av <- projection history a
    bv <- projection history b
    assertEqual (versionHistory av) (versionHistory bv)
    assertEqual (versionDependencies av) (versionDependencies bv)
    assertEqual 1 (Set.size (versionHistory av))
    assertEqual 2 (Map.size (versionDependencies av))

completeDependenciesTest :: IO ()
completeDependenciesTest = do
    let ((k1, k2, bk), fixture) = build Sha1 $ do
            (br, bt) <- root uuidB
            (_, builtBk) <- checkpoint bt br []
            (r, t) <- root uuidA
            (_, builtK1) <- checkpoint t r [builtBk]
            (_, builtK2) <- checkpoint t builtK1 []
            pure (builtK1, builtK2, builtBk)
    history <- expectRight (validate fixture [k2])
    first <- projection history k1
    second <- projection history k2
    assertEqual [bk] (Map.elems (versionDependencies first))
    assertEqual Map.empty (versionDependencies second)
    assertEqual (Right (Set.fromList [k1, k2])) (formalHistory history k2)

replaceDependencyTest :: IO ()
replaceDependencyTest = do
    let ((firstOid, secondOid, oldDependency, newDependency), fixture) = build Sha1 $ do
            (br, bt) <- root uuidB
            (_, oldVersion) <- checkpoint bt br []
            (_, newVersion) <- checkpoint bt oldVersion []
            (ar, at) <- root uuidA
            (_, firstVersion) <- checkpoint at ar [oldVersion]
            (_, secondVersion) <- checkpoint at firstVersion [newVersion]
            pure (firstVersion, secondVersion, oldVersion, newVersion)
    history <- expectRight (validate fixture [secondOid])
    first <- projection history firstOid
    second <- projection history secondOid
    assertEqual [oldDependency] (Map.elems (versionDependencies first))
    assertEqual [newDependency] (Map.elems (versionDependencies second))

transitiveVersionsTest :: IO ()
transitiveVersionsTest = do
    let ((tip, older, newer), fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (_, a1) <- checkpoint at ar []
            (_, a2) <- checkpoint at a1 []
            (br, bt) <- root uuidB
            (_, b) <- checkpoint bt br [a1]
            (cr, ct) <- root uuidC
            (_, c) <- checkpoint ct cr [b, a2]
            pure (c, a1, a2)
    history <- expectRight (validate fixture [tip])
    assertEqual (Right True) (isKnowledgeAncestor history older tip)
    assertEqual (Right True) (isKnowledgeAncestor history newer tip)

emptyContentTest :: IO ()
emptyContentTest = do
    let ((k1, k2, t), fixture) = build Sha1 $ do
            (r, builtT) <- root uuidA
            (_, builtK1) <- checkpoint builtT r []
            (_, builtK2) <- checkpoint builtT builtK1 []
            pure (builtK1, builtK2, builtT)
    history <- expectRight (validate fixture [k2])
    forM_ [k1, k2] $ \k -> projection history k >>= assertEqual t . versionTree

reusedContentTest :: IO ()
reusedContentTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (w, k) <- checkpoint t r []
            commit t [k, w]
    invalid (\e -> case e of ContentBaseMismatch _ _ _ -> True; _ -> False) fixture [tip]

mergeHistoryTest :: IO ()
mergeHistoryTest = do
    let ((a, b, merged), fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, builtA) <- checkpoint t r []
            (_, builtB) <- checkpoint t r []
            (_, builtMerged) <- checkpoint t builtA [builtB]
            pure (builtA, builtB, builtMerged)
    history <- expectRight (validate fixture [merged])
    formal <- projection history merged
    assertEqual (Set.fromList [a, b]) (versionHistory formal)
    assertEqual Map.empty (versionDependencies formal)
    assertEqual (Right (Set.fromList [a, b, merged])) (formalHistory history merged)
    assertEqual (Right True) (isFormalAncestor history b merged)

ancestryTrapTest :: IO ()
ancestryTrapTest = do
    let ((a1, a2, b), fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, builtA1) <- checkpoint t r []
            (br, bt) <- root uuidB
            (_, builtB) <- checkpoint bt br [builtA1]
            (_, builtA2) <- checkpoint t r [builtB]
            pure (builtA1, builtA2, builtB)
    history <- expectRight (validate fixture [a2])
    assertEqual (Right True) (isKnowledgeAncestor history a1 a2)
    assertEqual (Right False) (isFormalAncestor history a1 a2)
    assertEqual (Right False) (isFormalAncestor history b a2)
    assertEqual (Right (Set.singleton a2)) (formalHistory history a2)

missingCommitTest :: IO ()
missingCommitTest = do
    let (tip, fixture) = build Sha1 fresh
    invalid (\e -> e == ObjectUnavailable tip MissingObject) fixture [tip]

missingTreeTest :: IO ()
missingTreeTest = do
    let ((tip, t), fixture) = build Sha1 $ do
            builtT <- fresh
            builtTip <- commit builtT []
            pure (builtTip, builtT)
    invalid (\e -> e == ObjectUnavailable t MissingObject) fixture [tip]

incompleteTest :: IO ()
incompleteTest = do
    let (tip, fixture) = build Sha1 fresh
    forM_ [IncompleteHistory "shallow", WrongObjectType "blob", ObjectReadFailure "fixture read failed"] $ \problem -> do
        let provider = (source fixture){loadCommit = const (pure (Left problem))}
        assertEqual (Left (ObjectUnavailable tip problem)) $
            runIdentity (validateHistory Sha1 provider [tip])

cycleTest :: IO ()
cycleTest = do
    let (tip, fixture) = build Sha1 $ do
            (_, t) <- root uuidA
            builtTip <- fresh
            modify' (\f -> f{fixtureCommits = Map.insert builtTip (CommitObject t [builtTip]) (fixtureCommits f)})
            pure builtTip
    invalid (\e -> case e of CyclicHistory _ -> True; _ -> False) fixture [tip]

mixedFormatTest :: IO ()
mixedFormatTest = do
    let ((tip, t), fixture) = build Sha256 (root uuidA)
    assertEqual (Left (ObjectFormatMismatch tip)) (runIdentity (validateHistory Sha1 (source fixture) [tip]))
    let (bad, _) = build Sha1 fresh
        changed = fixture{fixtureCommits = Map.insert tip (CommitObject t [bad]) (fixtureCommits fixture)}
    invalid (\e -> e == ObjectFormatMismatch bad) changed [tip]

queryTest :: IO ()
queryTest = do
    let ((r, k, unknown), fixture) = build Sha1 $ do
            (builtR, t) <- root uuidA
            (_, builtK) <- checkpoint t builtR []
            builtUnknown <- fresh
            pure (builtR, builtK, builtUnknown)
    history <- expectRight (validate fixture [k])
    assertEqual (Left (UnknownCommit unknown)) (formalHistory history unknown)
    assertEqual (Left (ExpectedCheckpoint r)) (isFormalAncestor history r k)
    assertEqual (Right True) (isKnowledgeAncestor history k k)

cacheTest :: IO ()
cacheTest = do
    let ((a, b, c), fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            (_, builtA) <- checkpoint t r []
            (_, builtB) <- checkpoint t builtA []
            f <- get
            let sharedDirectory = case Map.lookup t (fixtureTrees f) of
                    Just [entry] -> entryObject entry
                    _ -> error "Invalid fixture tree"
            otherTree <- tree [TreeEntry uuidB Directory sharedDirectory]
            otherRoot <- commit otherTree []
            (_, builtC) <- checkpoint otherTree otherRoot []
            pure (builtA, builtB, builtC)
        record key result = do
            modify' (Map.insertWith (+) key (1 :: Int))
            pure result
        provider =
            HistorySource
                (\oid -> record (False, oid) (runIdentity (loadCommit (source fixture) oid)))
                (\oid -> record (True, oid) (runIdentity (loadTree (source fixture) oid)))
        (outcome, counts) = runState (validateHistory Sha1 provider [a, b, c, a, b, c]) Map.empty
    _ <- expectRight outcome
    assertTrue "An immutable object was loaded repeatedly" (all (== 1) (Map.elems counts))

-- Enumerate dependency choices and editing lengths for both object formats.
-- Compare projected reachability with an independent walk of raw Git parents.
graphProperties :: ObjectFormat -> IO ()
graphProperties format = forM_ [0 :: Int .. 7] $ \mask -> forM_ [1 :: Int .. 3] $ \editingLength -> do
    let ((tips, checkpoints), fixture) = build format $ do
            (ar, at) <- root uuidA
            (_, a1) <- checkpoint at ar []
            (br, bt) <- root uuidB
            (_, b1) <- checkpoint bt br [a1 | odd mask]
            (cr, ct) <- root uuidC
            (_, c1) <- checkpoint ct cr [b1 | odd (mask `div` 2)]
            w <- chain editingLength at a1
            a2 <- commit at ([a1, w] ++ [c1 | odd (mask `div` 4)])
            (_, side) <- checkpoint at a1 []
            (_, merged) <- checkpoint at a2 [side]
            pure ([merged, b1, c1], [a1, b1, c1, a2, side, merged])
    history <- expectRight (validate fixture tips)
    forM_ checkpoints $ \descendant -> do
        formal <- projection history descendant
        let node = versionNode formal
        sameHistory <- expectRight (formalHistory history descendant)
        forM_ (Set.toList sameHistory) $ \oid -> do
            retained <- projection history oid
            assertEqual node (versionNode retained)
        forM_ checkpoints $ \ancestor -> do
            let expected = rawAncestor fixture ancestor descendant
            actual <- expectRight (isKnowledgeAncestor history ancestor descendant)
            assertEqual expected actual
  where
    chain 0 _ parent = pure parent
    chain n t parent = commit t [parent] >>= chain (n - 1) t

rawAncestor :: Fixture -> ObjectId -> ObjectId -> Bool
rawAncestor fixture target start = walk Set.empty [start]
  where
    walk _ [] = False
    walk seen (oid : rest)
        | oid == target = True
        | Set.member oid seen = walk seen rest
        | otherwise = case Map.lookup oid (fixtureCommits fixture) of
            Nothing -> False
            Just object -> walk (Set.insert oid seen) (commitParents object ++ rest)
