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
import qualified GitRoam.Protocol.History as History
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Objects
import qualified GitRoam.Protocol.Repository as Repo
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
    directory <- tree $ [TreeEntry ".roam" RegularFile marker] ++ [TreeEntry "note.org" RegularFile marker | payload]
    tree [TreeEntry uuid Directory directory]

root :: BS.ByteString -> Build (ObjectId, ObjectId)
root uuid = do
    content <- nodeTree uuid False
    oid <- commit content []
    pure (oid, content)

source :: Fixture -> HistorySource Identity
source fixture =
    HistorySource
        (\oid -> pure (maybe (Left MissingObject) Right (Map.lookup oid (fixtureCommits fixture))))
        (\oid -> pure (maybe (Left MissingObject) Right (Map.lookup oid (fixtureTrees fixture))))

validate :: Fixture -> [ObjectId] -> Either History.HistoryError History.ValidatedHistory
validate fixture tips = runIdentity (History.validateHistory (fixtureFormat fixture) (source fixture) tips)

invalid :: (History.HistoryError -> Bool) -> Fixture -> [ObjectId] -> IO ()
invalid matches fixture tips = case validate fixture tips of
    Left problem -> assertTrue ("Unexpected v0.2.0 protocol error: " ++ show problem) (matches problem)
    Right _ -> ioError (userError "Accepted invalid v0.2.0 history")

requireCommit :: History.ValidatedHistory -> ObjectId -> IO History.ValidatedCommit
requireCommit history oid = maybe (ioError (userError "Missing validated commit")) pure (History.lookupCommit history oid)

main :: IO ()
main =
    runTests $
        [ ("canonical UUID labels", uuidTest)
        , ("invalid UUID labels", invalidUuidTest)
        , ("Root/Content and editable marker", contentTest)
        , ("a one-parent unchanged tree remains Content", emptyContentTest)
        , ("Root must contain only .roam", rootPayloadTest)
        , ("UUID tree isolation and .roam protection", malformedTreeTest)
        , ("Content first parent has the same identity", identityChangeTest)
        , ("two histories with one UUID and different Roots conflict", rootConflictTest)
        , ("forks from the same Root remain valid", forkTest)
        , ("explicit context preserves parent order and Git reachability", checkpointTest)
        , ("Checkpoint cannot change its first parent's tree", checkpointTreeTest)
        , ("context may point to Root and Content", contextKindsTest)
        , ("same-Node context overlaps the managed tree", overlappingContextTest)
        , ("context histories with conflicting Roots reject", contextRootConflictTest)
        , ("exact repeated parent OIDs reject", duplicateParentsTest)
        , ("reference validity does not require context branch retention", localRefsTest)
        , ("ordinary transition protects Root but not old Checkpoints", transitionTest)
        , ("managed ref identities and missing tips are checked", refIdentityTest)
        , ("ordinary transitions reject a changed Root", rootTransitionTest)
        , ("missing commit/tree evidence rejects", missingObjectTest)
        , ("incomplete history and wrong-type objects reject", incompleteTest)
        , ("cyclic provider evidence rejects", cycleTest)
        , ("mixed object formats reject", mixedFormatTest)
        , ("unknown query starts are rejected", unknownQueryTest)
        , ("multi-start reachability shares common ancestry", multiStartReachabilityTest)
        , ("immutable objects are memoized", cacheTest)
        ]
            ++ [("independent SHA formats " ++ show format, formatTest format) | format <- [Sha1, Sha256]]

uuidTest :: IO ()
uuidTest =
    forM_
        [ uuidA
        , "00000000-0000-0000-0000-000000000000"
        , "ffffffff-ffff-ffff-ffff-ffffffffffff"
        , "abcdef01-2345-1678-9abc-def012345678"
        ]
        $ \bytes -> do
            node <- expectRight (parseNodeId bytes)
            assertEqual bytes (nodeIdBytes node)

invalidUuidTest :: IO ()
invalidUuidTest =
    mapM_
        (expectLeft . parseNodeId)
        [ BS.empty
        , "ABCDEF01-2345-1678-9abc-def012345678"
        , "11111111111141118111111111111111"
        , uuidA <> "\n"
        , BS.replicate 36 255
        ]

contentTest :: IO ()
contentTest = do
    let ((r, c, updated), fixture) = build Sha1 $ do
            (builtRoot, _) <- root uuidA
            changedMarker <- nodeTree uuidA False
            builtContent <- commit changedMarker [builtRoot]
            content <- nodeTree uuidA True
            next <- commit content [builtContent]
            pure (builtRoot, builtContent, next)
    history <- expectRight (validate fixture [updated])
    first <- requireCommit history c
    final <- requireCommit history updated
    assertEqual (History.Content r) (History.validatedKind first)
    assertEqual (History.Content c) (History.validatedKind final)
    assertEqual (History.validatedRoot first) (History.validatedRoot final)

emptyContentTest :: IO ()
emptyContentTest = do
    let ((r, c), fixture) = build Sha1 $ do
            (builtRoot, content) <- root uuidA
            next <- commit content [builtRoot]
            pure (builtRoot, next)
    history <- expectRight (validate fixture [c])
    value <- requireCommit history c
    assertEqual (History.Content r) (History.validatedKind value)
    assertEqual [] =<< expectRight (History.contextParents history c)

rootPayloadTest :: IO ()
rootPayloadTest = do
    let (tip, fixture) = build Sha1 (nodeTree uuidA True >>= \content -> commit content [])
    invalid (\e -> case e of History.InvalidNodeTree _ History.RootContainsContent -> True; _ -> False) fixture [tip]

malformedTreeTest :: IO ()
malformedTreeTest = do
    let (tips, fixture) = build Sha1 $ do
            blob <- fresh
            good <- tree [TreeEntry ".roam" RegularFile blob]
            badMarker <- tree [TreeEntry "note.org" RegularFile blob]
            linkMarker <- tree [TreeEntry ".roam" SymbolicLink blob]
            directoryMarker <- tree [TreeEntry ".roam" Directory good]
            duplicate <- tree [TreeEntry ".roam" RegularFile blob, TreeEntry ".roam" RegularFile blob]
            badName <- tree [TreeEntry "a/b" RegularFile blob, TreeEntry ".roam" RegularFile blob]
            mapM
                (\entries -> tree entries >>= \content -> commit content [])
                [ []
                , [TreeEntry uuidA Directory good, TreeEntry "outside" RegularFile blob]
                , [TreeEntry uuidA RegularFile blob]
                , [TreeEntry "invalid-uuid" Directory good]
                , [TreeEntry uuidA Directory badMarker]
                , [TreeEntry uuidA Directory linkMarker]
                , [TreeEntry uuidA Directory directoryMarker]
                , [TreeEntry uuidA Directory duplicate]
                , [TreeEntry uuidA Directory badName]
                ]
    forM_ tips $ \tip ->
        invalid (\e -> case e of History.InvalidNodeTree _ _ -> True; _ -> False) fixture [tip]

identityChangeTest :: IO ()
identityChangeTest = do
    let (tip, fixture) = build Sha1 $ do
            (r, _) <- root uuidA
            newTree <- nodeTree uuidB True
            commit newTree [r]
    invalid (\e -> case e of History.IdentityChanged _ _ _ -> True; _ -> False) fixture [tip]

rootConflictTest :: IO ()
rootConflictTest = do
    let (tips, fixture) = build Sha1 $ do
            (r, t) <- root uuidA
            other <- commit t []
            pure [r, other]
    invalid (\e -> case e of History.ConflictingRoots _ _ _ -> True; _ -> False) fixture tips

forkTest :: IO ()
forkTest = do
    let ((r, a, b), fixture) = build Sha1 $ do
            (builtRoot, content) <- root uuidA
            first <- commit content [builtRoot]
            second <- commit content [builtRoot]
            pure (builtRoot, first, second)
    history <- expectRight (validate fixture [a, b])
    forM_ [a, b] $ \oid -> do
        value <- requireCommit history oid
        assertEqual r (History.validatedRoot value)

checkpointTest :: IO ()
checkpointTest = do
    let ((ar, a, k, br, cr), fixture) = build Sha1 $ do
            (builtAr, _) <- root uuidA
            edited <- nodeTree uuidA True
            builtA <- commit edited [builtAr]
            (builtBr, _) <- root uuidB
            (builtCr, _) <- root uuidC
            builtK <- commit edited [builtA, builtBr, builtCr]
            pure (builtAr, builtA, builtK, builtBr, builtCr)
    history <- expectRight (validate fixture [k])
    value <- requireCommit history k
    assertEqual (History.Checkpoint a [br, cr]) (History.validatedKind value)
    assertEqual [br, cr] =<< expectRight (History.contextParents history k)
    assertEqual [k, a, ar] =<< expectRight (History.firstParentHistory history k)
    assertEqual (Set.fromList [ar, a, k, br, cr]) =<< expectRight (History.reachableHistory history k)

checkpointTreeTest :: IO ()
checkpointTreeTest = do
    let (k, fixture) = build Sha1 $ do
            (ar, _) <- root uuidA
            (br, _) <- root uuidB
            other <- nodeTree uuidA True
            commit other [ar, br]
    invalid (\e -> case e of History.CheckpointTreeMismatch _ _ -> True; _ -> False) fixture [k]

contextKindsTest :: IO ()
contextKindsTest = do
    let ((k, br, cr), fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (builtBr, _) <- root uuidB
            (builtCr, contentC) <- root uuidC
            builtCc <- commit contentC [builtCr]
            builtK <- commit at [ar, builtBr, builtCc]
            pure (builtK, builtBr, builtCc)
    history <- expectRight (validate fixture [k])
    assertEqual [br, cr] =<< expectRight (History.contextParents history k)

overlappingContextTest :: IO ()
overlappingContextTest = do
    let (k, fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            a <- commit at [ar]
            commit at [a, ar]
    invalid (\e -> case e of History.OverlappingContextTree _ _ -> True; _ -> False) fixture [k]

contextRootConflictTest :: IO ()
contextRootConflictTest = do
    let (k, fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (br, bt) <- root uuidB
            other <- commit bt []
            commit at [ar, br, other]
    invalid (\e -> case e of History.ConflictingRoots _ _ _ -> True; _ -> False) fixture [k]

duplicateParentsTest :: IO ()
duplicateParentsTest = do
    let (k, fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (br, _) <- root uuidB
            commit at [ar, br, br]
    invalid (\e -> case e of History.DuplicateParents _ -> True; _ -> False) fixture [k]

localRefsTest :: IO ()
localRefsTest = do
    let ((a, bOld, bNew), fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (br, bt) <- root uuidB
            old <- commit bt [br]
            rewritten <- commit bt [br]
            checkpoint <- commit at [ar, old]
            pure (checkpoint, old, rewritten)
    history <- expectRight (validate fixture [a, bNew])
    aid <- expectRight (parseNodeId uuidA)
    bid <- expectRight (parseNodeId uuidB)
    before <- expectRight (Repo.validateManagedState history (Map.fromList [(aid, a), (bid, bOld)]))
    after <- expectRight (Repo.validateManagedState history (Map.fromList [(aid, a), (bid, bNew)]))
    _ <- expectRight (Repo.validateOrdinaryTransition before after)
    _ <- expectRight (Repo.validateManagedState history (Map.singleton aid a))
    assertEqual [bOld] =<< expectRight (History.contextParents history a)

transitionTest :: IO ()
transitionTest = do
    let ((r, ordinary, k), fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (br, _) <- root uuidB
            builtOrdinary <- commit at [ar]
            builtK <- commit at [builtOrdinary, br]
            pure (ar, builtOrdinary, builtK)
    history <- expectRight (validate fixture [k])
    aid <- expectRight (parseNodeId uuidA)
    before <- expectRight (Repo.validateManagedState history (Map.singleton aid k))
    after <- expectRight (Repo.validateManagedState history (Map.singleton aid ordinary))
    _ <- expectRight (Repo.validateOrdinaryTransition before after)
    empty <- expectRight (Repo.validateManagedState history Map.empty)
    assertEqual (Left [Repo.NodeBranchRemoved aid]) (Repo.validateOrdinaryTransition before empty)
    value <- requireCommit history ordinary
    assertEqual r (History.validatedRoot value)

refIdentityTest :: IO ()
refIdentityTest = do
    let ((ar, br, unknown), fixture) = build Sha1 $ do
            (a, _) <- root uuidA
            (b, _) <- root uuidB
            missing <- fresh
            pure (a, b, missing)
    history <- expectRight (validate fixture [ar, br])
    aid <- expectRight (parseNodeId uuidA)
    bid <- expectRight (parseNodeId uuidB)
    assertEqual (Left [Repo.RefIdentityMismatch aid bid br]) (Repo.validateManagedState history (Map.singleton aid br))
    assertEqual (Left [Repo.UnknownNodeTip aid unknown]) (Repo.validateManagedState history (Map.singleton aid unknown))

rootTransitionTest :: IO ()
rootTransitionTest = do
    let ((firstRoot, secondRoot), fixture) = build Sha1 $ do
            (first, treeOid) <- root uuidA
            second <- commit treeOid []
            pure (first, second)
    -- The two Roots are deliberately validated in separate local snapshots;
    -- validating their union must fail the UUID uniqueness invariant.
    firstHistory <- expectRight (validate fixture [firstRoot])
    secondHistory <- expectRight (validate fixture [secondRoot])
    aid <- expectRight (parseNodeId uuidA)
    before <- expectRight (Repo.validateManagedState firstHistory (Map.singleton aid firstRoot))
    after <- expectRight (Repo.validateManagedState secondHistory (Map.singleton aid secondRoot))
    assertEqual
        (Left [Repo.NodeRootChanged aid firstRoot secondRoot])
        (Repo.validateOrdinaryTransition before after)

missingObjectTest :: IO ()
missingObjectTest = do
    let (tip, fixture) = build Sha1 fresh
    invalid (== History.ObjectUnavailable tip MissingObject) fixture [tip]
    let ((missing, c), fixture2) = build Sha1 $ do
            missingTree <- fresh
            built <- commit missingTree []
            pure (missingTree, built)
    invalid (== History.ObjectUnavailable missing MissingObject) fixture2 [c]

incompleteTest :: IO ()
incompleteTest = do
    let (tip, fixture) = build Sha1 fresh
    forM_ [IncompleteHistory "shallow", WrongObjectType "blob", ObjectReadFailure "read failure"] $ \problem -> do
        let provider = (source fixture){loadCommit = const (pure (Left problem))}
        assertEqual (Left (History.ObjectUnavailable tip problem)) $
            runIdentity (History.validateHistory Sha1 provider [tip])

cycleTest :: IO ()
cycleTest = do
    let (tip, fixture) = build Sha1 $ do
            (_, t) <- root uuidA
            oid <- fresh
            modify' (\f -> f{fixtureCommits = Map.insert oid (CommitObject t [oid]) (fixtureCommits f)})
            pure oid
    invalid (\e -> case e of History.CyclicHistory _ -> True; _ -> False) fixture [tip]

mixedFormatTest :: IO ()
mixedFormatTest = do
    let ((tip, t), fixture) = build Sha256 (root uuidA)
    assertEqual (Left (History.ObjectFormatMismatch tip)) (runIdentity (History.validateHistory Sha1 (source fixture) [tip]))
    let (bad, _) = build Sha1 fresh
        changed = fixture{fixtureCommits = Map.insert tip (CommitObject t [bad]) (fixtureCommits fixture)}
    invalid (== History.ObjectFormatMismatch bad) changed [tip]

unknownQueryTest :: IO ()
unknownQueryTest = do
    let ((r, unknown), fixture) = build Sha1 $ do
            (builtR, _) <- root uuidA
            missing <- fresh
            pure (builtR, missing)
    history <- expectRight (validate fixture [r])
    assertEqual (Left (History.UnknownCommit unknown)) (History.firstParentHistory history unknown)
    assertEqual (Left (History.UnknownCommit unknown)) (History.contextParents history unknown)
    assertEqual (Left (History.UnknownCommit unknown)) (History.reachableHistory history unknown)

multiStartReachabilityTest :: IO ()
multiStartReachabilityTest = do
    let ((rootOids, bContent, aCheckpoint, cCheckpoint, unknown), fixture) = build Sha1 $ do
            (aRoot, aTree) <- root uuidA
            (bRoot, bTree) <- root uuidB
            (cRoot, cTree) <- root uuidC
            bTip <- commit bTree [bRoot]
            aTip <- commit aTree [aRoot, bTip]
            cTip <- commit cTree [cRoot, bTip]
            missing <- fresh
            pure ([aRoot, bRoot, cRoot], bTip, aTip, cTip, missing)
    history <- expectRight (validate fixture [aCheckpoint, cCheckpoint])
    let expected = Set.fromList (rootOids ++ [bContent, aCheckpoint, cCheckpoint])
    assertEqual expected
        =<< expectRight (History.reachableHistoryFrom history [aCheckpoint, cCheckpoint])
    assertEqual expected
        =<< expectRight (History.reachableHistoryFrom history [aCheckpoint, cCheckpoint, aCheckpoint])
    assertEqual Set.empty
        =<< expectRight (History.reachableHistoryFrom history [])
    assertEqual
        (Left (History.UnknownCommit unknown))
        (History.reachableHistoryFrom history [aCheckpoint, unknown])
    fromA <- expectRight (History.reachableHistory history aCheckpoint)
    fromC <- expectRight (History.reachableHistory history cCheckpoint)
    assertEqual (Set.union fromA fromC)
        =<< expectRight (History.reachableHistoryFrom history [aCheckpoint, cCheckpoint])

cacheTest :: IO ()
cacheTest = do
    let ((a, b), fixture) = build Sha1 $ do
            (ar, at) <- root uuidA
            (br, bt) <- root uuidB
            builtB <- commit bt [br]
            builtA <- commit at [ar, builtB]
            pure (builtA, builtB)
        record key result = do
            modify' (Map.insertWith (+) key (1 :: Int))
            pure result
        provider =
            HistorySource
                (\oid -> record (False, oid) (runIdentity (loadCommit (source fixture) oid)))
                (\oid -> record (True, oid) (runIdentity (loadTree (source fixture) oid)))
        (outcome, counts) = runState (History.validateHistory Sha1 provider [a, b, a, b]) Map.empty
    _ <- expectRight outcome
    assertTrue "An immutable object was loaded more than once" (all (== 1) (Map.elems counts))

formatTest :: ObjectFormat -> IO ()
formatTest format = do
    let ((ar, br, k), fixture) = build format $ do
            (a, at) <- root uuidA
            (b, _) <- root uuidB
            checkpoint <- commit at [a, b]
            pure (a, b, checkpoint)
    history <- expectRight (validate fixture [k])
    assertEqual [br] =<< expectRight (History.contextParents history k)
    assertEqual [k, ar] =<< expectRight (History.firstParentHistory history k)
    assertEqual (Set.fromList [ar, br, k]) =<< expectRight (History.reachableHistory history k)
