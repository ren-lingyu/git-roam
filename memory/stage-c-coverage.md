# Stage C requirement-to-test audit

Baseline: exact main d8503afd02ae02ab38c604888c0c84e1e2a3cbdb test and application
sources, plus the three staged documentation blobs described in SOURCE.json.
References below are project-relative source paths and test functions, not a
claim that every matrix combination was executed. Runtime completion and authorization history are recorded in [stage-c-verification.md](stage-c-verification.md).
The isolated SUITES.json enumerates all 14 Cabal suites from the real manifest;
tests are not independently redefined in Nix. No product or test source changes were made.

| C obligation | Existing evidence and checked assertions | Scope / assessment |
| --- | --- | --- |
| Root/Content/Checkpoint encoding | Protocol.hs contentTest, emptyContentTest, checkpointTest, checkpointTreeTest, contextKindsTest; Checkpoint.hs structure. | Pure graph checks plus native construction on files/reftable x SHA-1/SHA-256. Root can directly precede Checkpoint; consecutive Checkpoints preserve the current tree, with no bridge Content. |
| Context kind/order/no inheritance | Checkpoint.hs structure compares exact ordered raw parents, then narrows the next list to only B Root; EndToEnd.hs lifecycle records external Checkpoints. | External Root/Content and direct Checkpoint contexts are represented; same-Node duplicate/version distinctions are asserted. |
| Invalid/ambiguous context input | Checkpoint.hs arguments, invalid, referenceInputs, repeatedNodeWarning; Protocol.hs duplicateParentsTest, overlappingContextTest. | Explicit context required, refs/annotated tags/abbreviated OIDs accepted, duplicate/self contexts refused; same external Node versions accepted with CLI warning. |
| Historical anchoring after advance/rewrite/delete | Checkpoint.hs structure advances B then moves it backwards/deletes its branch and re-inspects A; orphan selects an unretained Content; Protocol.hs localRefsTest; Deletion.hs historical/merged; EndToEnd.hs lifecycle. | No requirement to establish or retain a source Checkpoint/branch. Actual non-cascading deletion and parent-based retention are checked. Some setup updates explicitly bypass only the fixture's own Hook; ordinary rewrites are covered separately below. |
| UUID/Root/tree isolation | Protocol.hs uuidTest, invalidUuidTest, malformedTreeTest, identityChangeTest, rootConflictTest, contextRootConflictTest; Inspection.hs identityTest/rootConflictTest; Protection.hs crossRoot. | Protocol accepts canonical labels independently of create's v4/Nil/Max policy. Conflicting external Roots cannot bypass full-state Checkpoint validation. |
| Stored evidence and raw ancestry | Inspection.hs missingBlobTest, missingCommitTest, replaceTest, graftTest, nestedObjectsTest, shallowTest; Batch.hs malformed scenarios/cancellation/resource cases. | Missing/wrong-type/nested evidence, replace/graft isolation and shallow refusal are represented. Graft test checks shared candidate validation and installed Hook too. Most destructive-evidence edge cases use files/SHA-1, not every backend combination. |
| Node scope/status/inference | Inspection.hs scopeTest/cliTest/worktreeTest/bareTest; Checkpoint.hs selection/mainWorktreeInference/inferNodeCli. | Selected Node excludes unrelated bad branches; status shows direct latest context with Content tail. Main and linked UUID HEAD inference plus detached/ordinary rejection are explicit. Bare inspection is tested; not every command is exercised in bare repositories. |
| Native Content/amend/same-Root rewrite | Protection.hs matrix; Inspection.hs protectionTest/transitionTest. | files/reftable x SHA-1/SHA-256; real installed Hook accepts native commit/amend/reset and valid Checkpoint updates, rejects uncontrolled UUID branch deletion/creation and malformed histories. No claim of exercising every possible rebase/merge workflow. |
| Multi-ref candidate and old-value semantics | Protection.hs matrix/invalidInput/crossRoot; EndToEnd.hs lifecycle real update-ref transaction. | Full candidate validation and all-zero old input handling; Root conflict fallback; real multi-ref update on all four backend/format combinations. |
| Conditional update races and locks | Checkpoint.hs competingRef/competingContextRef; Deletion.hs targetRace/verifyRace/staleConfig/staleCheckout; Deployment.hs racingRefs/competingCreation; Protection.hs locking. | Deterministic injected races and native expected-old/verify refusal, not arbitrary-process stress testing or serializability proof. |
| Other Hooks/failure residuals | Checkpoint.hs otherHook/postInstallFailure; Deletion.hs otherHook/lostResponse/failedCleanup; Deployment.hs cleanFailure/dirtyFailure; Worktree.hs failedAdd; Inspection.hs hookCoexistenceTest. | Other named Hooks remain active, refusal or lost responses report actual state, user data and concurrent winners are retained. |
| Deletion semantics and managed-only reachability | Deletion.hs basic/historical/merged/outgoing/configuration/readOnly/stale; Protocol.hs multiStartReachabilityTest. | Does not cascade into context recorders; exact exclusive sets, surviving objects, remote refs/config isolation, confirmation binding and read-only preview. Main/manual/moved checkouts block; detached checkout stays. |
| Interactive and noninteractive deletion | Deletion.hs cli and interactive True/False. | Exact preview-bound authorization and refusal through real PTY tests, principally files/SHA-1. |
| Deploy/clone/fetch/remote ambiguity | Deployment.hs batch/cloneFlow/equalSources/ambiguity/independentSources/invalidTargets; EndToEnd.hs lifecycle. | Whole-set deployment, fetched tracking setup, no advance of existing branches, no source-branch closure requirement, explicit divergent-remote selection. Positive backend/format matrix. |
| Worktree user data, path/index conflicts | Worktree.hs paths/trackedTarget/trackedAncestor/occupiedTarget/moved/dirty; Checkpoint.hs dirty/dirtyState/dirtyMain; Undeployment.hs dirtyPreflight/ignoredLocked. | Staged/unstaged/untracked/ignored state, symlink/byte paths, moved/dirty existing deployments and target-only index conflicts. MERGE_HEAD is explicitly tested in Worktree dirty; other in-progress markers share production checks but do not each have a distinct fixture. |
| Worktree lifecycle and compensation | Worktree.hs stale/nestedRemoval/foreignNested/specialStates/failedAdd; Undeployment.hs mainWorktree/excludedWorktrees/nestedConflict/removedCwd/partialFailure/lostResult/lateEdits/changedRefs/invalidState. | Main/detached/ordinary non-targets, nesting, locks, prunable/stale plans, whole preflight and safe partial-failure reporting. No cross-worktree atomicity promise. |
| Whole public workflow | EndToEnd.hs lifecycle. | Four SHA/object-ref combinations use real CLI/installed Hook, local bare push/clone/fetch, unsafe/safe FF, actual multi-ref updates, deployment and non-cascading deletion. Representative lifecycle, not literal execution of every README line. |
| Other retained foundations | Unit.hs, GitAdapter.hs, Creation.hs, Output.hs, Batch.hs. | Help/parser, binary argv/transport, identity generation/output formats and scoped reader safety remain in the same full run. |

## Assessment

The adopted C semantic groups have maintained tests; this audit found no missing
required feature that justifies duplicating tests or patching product source.
Coverage is layered: pure protocol, native adapter/application, deterministic
race injection and representative CLI/Hook integration are complementary.
Do not describe every negative case as independently tested on all four
backend/format combinations. The exact minimum Git 2.54, other Nix systems,
arbitrary external writer stress, cold-cache performance and every README
walkthrough step remain outside the demonstrated evidence. These are limits,
not an invitation to expand this task into compatibility or performance work.

Actual pass/fail counts and timeout status are distilled in
[stage-c-verification.md](stage-c-verification.md); local REPORT.md and RESULTS.json
are under tmp/v020-stage-c-verification/, not durable memory dependencies. Source inspection and an existing cached package result alone
are not labelled a fresh full-suite pass.
