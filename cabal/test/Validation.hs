{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import BatchFixture
import qualified Data.ByteString.Char8 as BSC
import Data.IORef
import Data.List (isInfixOf)
import qualified Data.Map.Strict as Map
import qualified GitRoam.Application.Checkpoint as Checkpoint
import qualified GitRoam.Application.Create as Create
import qualified GitRoam.Application.Delete as Delete
import qualified GitRoam.Application.Deploy as Deploy
import qualified GitRoam.Application.Inspect as Inspect
import qualified GitRoam.Application.Protection as Protection
import qualified GitRoam.Application.Undeploy as Undeploy
import GitRoam.Application.Validation
import GitRoam.Application.Worktree (loadOperationState)
import GitRoam.Git
import GitRoam.ObjectId
import GitRoam.Protocol.Identity
import GitRoam.Protocol.Repository
import System.Directory (doesPathExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import TestSupport
import WorktreeFixture

main :: IO ()
main =
    runBatchFixture $
        runTests
            [ (backend ++ "/" ++ show format ++ ": " ++ name, fixture backend format test)
            | backend <- ["files", "reftable"]
            , format <- [Sha1, Sha256]
            , (name, test) <-
                [ ("validation is independent of worktree observations", independent)
                , ("branch identity is required for trusted state", identity)
                , ("strict readers and Hook reject incomplete refs", incomplete)
                , ("ref changes override provisional worktree failures", changed)
                , ("native failed session never yields trusted state", session)
                , ("all management entry points retain registration preflight", operations)
                ]
            ]

type Scenario = Git IO -> FilePath -> FilePath -> FilePath -> IO ()

withoutWorktrees :: Git IO -> Git IO
withoutWorktrees git = Git $ \invocation ->
    if all (`elem` gitArguments invocation) ["worktree", "list"]
        then pure (Left (GitTransportError "injected registration read failure"))
        else runGit git invocation

independent :: Scenario
independent git _ repo _ = do
    root git repo nodeA
    state <- loadManagedState (withoutWorktrees git) repo >>= expectRight
    _ <- validateCandidate (withoutWorktrees git) repo (managedRefs state) >>= expectRight
    loadOperationState (withoutWorktrees git) repo >>= expectLeft
    Inspect.inspectState (withoutWorktrees git) repo [] Nothing >>= expectLeft
    calls <- newIORef []
    let observed = Git $ \invocation -> do
            modifyIORef' calls (gitArguments invocation :)
            runGit git invocation
    _ <- loadManagedState observed repo >>= expectRight
    arguments <- readIORef calls
    assertTrue "validation must not query worktree/status metadata" $
        all (\args -> not (any (`elem` args) ["worktree", "status", "log", "show"])) arguments

identity :: Scenario
identity git _ repo _ = do
    root git repo nodeA
    root git repo nodeB
    state <- loadManagedState git repo >>= expectRight
    let wrong = Map.singleton nodeA (managedRefs state Map.! nodeB)
    validateCandidate git repo wrong >>= expectLeft
    _ <- ok git repo ["update-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeA), BSC.unpack (objectIdBytes (wrong Map.! nodeA))] ""
    outcome <- loadManagedState git repo
    case outcome of
        Left (CandidateStateInvalid problems) -> assertTrue "identity evidence retained" (not (null problems))
        _ -> fail (show outcome)
    report <- Inspect.inspectState git repo [] Nothing >>= expectRight
    assertTrue "legacy check still reports invalid identity" (not (null (Inspect.reportProblems report)))

incomplete :: Scenario
incomplete git _ repo _ = do
    root git repo nodeA
    state <- loadManagedState git repo >>= expectRight
    let oid = objectIdBytes (managedRefs state Map.! nodeA)
        input = oid <> " " <> oid <> " refs/heads/" <> nodeIdBytes nodeA <> "\n"
        faults =
            [ ("warning", \value -> Right value{gitStderr = "warning: incomplete enumeration\n"})
            , ("malformed", \value -> Right value{gitStdout = gitStdout value <> "broken\n"})
            , ("duplicate", \value -> Right value{gitStdout = gitStdout value <> gitStdout value})
            , ("command failure", \value -> Right value{gitExitCode = ExitFailure 128})
            , ("transport failure", const (Left (GitTransportError "injected ref failure")))
            ]
    mapM_
        ( \(name, fault) -> do
            let failing = Git $ \invocation -> do
                    response <- runGit git invocation
                    pure $ if "for-each-ref" `elem` gitArguments invocation then response >>= fault else response
            loadManagedState failing repo >>= expectLeft
            loadOperationState failing repo >>= expectLeft
            result <- Protection.evaluateTransaction failing repo "prepared" input
            assertTrue ("Hook accepted " ++ name) (case result of Left _ -> True; Right _ -> False)
        )
        faults
    assertEqual (managedRefs state) . managedRefs =<< (loadManagedState git repo >>= expectRight)
    -- A native symbolic Node is a complete observation, but remains forbidden
    -- for whole-set validation and Hook transactions, even when updating A.
    _ <- ok git repo ["update-ref", "refs/heads/ordinary", BSC.unpack oid] ""
    _ <- ok git repo ["symbolic-ref", BSC.unpack ("refs/heads/" <> nodeIdBytes nodeB), "refs/heads/ordinary"] ""
    loadManagedState git repo >>= assertEqual (Left (SymbolicNodeBranch nodeB "refs/heads/ordinary"))
    loadOperationState git repo >>= expectLeft
    Protection.evaluateTransaction git repo "prepared" input >>= assertEqual (Left "Symbolic Node branches cannot be updated")

changed :: Scenario
changed git _ repo _ = do
    root git repo nodeA
    calls <- newIORef (0 :: Int)
    let racing = Git $ \invocation -> do
            response <- runGit (withoutWorktrees git) invocation
            if "for-each-ref" `elem` gitArguments invocation
                then do
                    number <- atomicModifyIORef' calls (\n -> (n + 1, n + 1))
                    pure $ if number == 2 then fmap (\value -> value{gitStdout = ""}) response else response
                else pure response
    outcome <- loadOperationState racing repo
    assertTrue "reference change must take precedence over failed registration" $
        case outcome of Left problem -> "ReferencesChanged" `isInfixOf` problem; Right _ -> False
    assertEqual 2 =<< readIORef calls

session :: Scenario
session git _ repo parent = do
    root git repo nodeA
    state <- loadManagedState git repo >>= expectRight
    failing <- fixtureGit "commit-nonzero" parent
    projected <- newIORef False
    outcome <- withValidationEvidence failing repo [] Nothing $ \evidence -> do
        writeIORef projected True
        pure (validateEvidence evidence)
    assertEqual True =<< readIORef projected
    expectLeft outcome
    loadManagedState failing repo >>= expectLeft
    loadOperationState failing repo >>= expectLeft
    validateCandidate failing repo (managedRefs state) >>= expectLeft
    Inspect.inspectState failing repo [] Nothing >>= expectLeft
    let oid = objectIdBytes (managedRefs state Map.! nodeA)
    Protection.evaluateTransaction
        failing
        repo
        "prepared"
        (oid <> " " <> oid <> " refs/heads/" <> nodeIdBytes nodeA <> "\n")
        >>= expectLeft

operations :: Scenario
operations git executable repo parent = do
    root git repo nodeA
    root git repo nodeB
    enable git executable repo
    before <- loadManagedState git repo >>= expectRight
    preview <- Delete.previewDelete git repo nodeB >>= expectRight
    authorization <- maybe (fail "expected executable delete preview") pure (Delete.deletePlanId preview)
    calls <- newIORef []
    let failing = Git $ \invocation -> do
            modifyIORef' calls (gitArguments invocation :)
            runGit (withoutWorktrees git) invocation
        nodeC = either error id (parseNodeId "33333333-3333-4333-8333-333333333333")
        context = BSC.unpack (objectIdBytes (managedRefs before Map.! nodeB))
    Create.createNodeWith (pure nodeC) executable failing repo (parent </> "created") >>= registrationFailure
    Checkpoint.checkpoint executable failing repo (Just nodeA) "message" [context] >>= registrationFailure
    Undeploy.undeploy executable failing repo >>= registrationFailure
    Delete.previewDelete failing repo nodeB >>= registrationFailure
    Delete.executeDelete executable failing repo nodeB authorization >>= registrationFailure
    Deploy.deploy executable failing repo (parent </> "deployment") Nothing >>= registrationFailure
    after <- loadManagedState git repo >>= expectRight
    assertEqual (managedRefs before) (managedRefs after)
    mapM_ (\path -> doesPathExist (parent </> path) >>= assertEqual False) ["created", "deployment"]
    arguments <- readIORef calls
    assertTrue "failed preflight must precede ref/object/worktree writes" $
        all (\args -> not (any (`elem` args) ["update-ref", "commit-tree", "mktree", "add", "remove"])) arguments
  where
    registrationFailure result = case result of
        Left problem -> assertTrue ("unexpected refusal: " ++ show problem) ("injected registration read failure" `isInfixOf` show problem)
        Right _ -> fail "management operation accepted unreadable registration"
