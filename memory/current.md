# Git Roam current state

## Objective and actual progress

Current objective: complete the v0.2.0 context-Checkpoint redesign by
performing the production cutover. v0.1.0 is finalized, tagged and documented as
the first implementation. Six isolated preparation commits are in place: the V2
pure protocol, retirement of the v0.1.0 `discard` workflow, native inspection,
context Checkpoint construction, reference-transaction validation and
non-cascading Node deletion, each with its own V2 test suite; every Cabal
component builds with `-Werror`. A development handoff now fixes the cutover
strategy: stop adding parallel `Application.V2.*` modules, refactor the formal
modules against the V2 prototype, and switch every public command and the
installed Hook in one buildable sequence. The production CLI, Hook, Create,
Deploy and Undeploy still run the v0.1.0 protocol, so the development branch is
not yet a usable v0.2.0 implementation. The user confirms no actual callers and
no workflow built on v0.1.0, so no existing deployment requires migration. Do
not promise automatic compatibility between the two protocols.

At inspection, project main HEAD is `feat(deletion): add isolated v0.2.0 native
Node deletion`, directly after `feat(protection): add isolated v0.2.0 reference
transaction validation`, `feat(checkpoint): add isolated v0.2.0 context
checkpoint construction`, `feat(inspection): add isolated v0.2.0 native history
validation`, `refactor(discard): retire formal-history discard workflow` and
`feat(protocol): introduce isolated v0.2.0 history model`. Project main and
`origin/main` agree. Earlier commits finalized v0.1.0 (`DONE v0.1.0` with
`CLOSED: [2026-11-07 Sat 18:59]` UTC and the annotated tag `v0.1.0`), added the
detailed `CHANGELOGS/v0.1.0.org` manuscript, and documented the v0.2.0 direction
in `README.org` and a `TODO v0.2.0` checklist in `CHANGELOG.org`, where only the
retired-Discard item is checked. README still documents the v0.1.0 protocol for
the remaining commands. No publication evidence has been observed and a tag is
not proof of publication. Alternative deployment naming and full-deployment
acceleration remain outside the v0.1.0 release scope.

The original serial implementation plan was accepted on 2026-11-01 and is now
complete. The detailed milestone and verification history follows.

The mandatory design checkpoint and user-committed project node 0 are complete.
The committed CHANGELOG matches the staged review. The corrected Git-source root
flake check passed on x86_64-linux, resolving the earlier treefmt blocker for
tracked source. It reused available results and did not validate other platforms.

The independent standard-Git experiment is complete: final unpatched Git 2.56.0
fixtures passed 66/66 on x86_64-linux, including files/reftable and SHA-256 smoke.
Findings and execution consequences are reviewed; the node-1 experimental gate
is satisfied for this pinned Git. No minimum-2.54 or broader safety claim follows.
Project node 1 is now committed: CLI help/version, library, binary
Git transport, opaque SHA-1/SHA-256 OIDs, repository discovery, two test suites,
Nix Git selection and README. Formatting, build, all 12 unit and nine integration
cases, and flake check passed on x86_64-linux. The user committed node 1 as
feat(git-roam): add CLI and native Git foundations. Read-only comparison confirmed
all 20 committed source files match the verified GHC 9.12 snapshot, and the project
worktree was clean at transition. Node 2 is now committed: pure permanent history
protocol and projection, with
corresponding tests and README. Its final build passed 36 protocol cases and the
existing 21 cases, with no compiler warnings, and flake check passed. No new CLI
command was advertised by node 2. Its user commit was confirmed against all 24
files in the tested snapshot. Node 3 is committed by the user, and all 28
committed source files match the verified snapshot.
Its final pre-commit build passed all 79 cases with no
compiler warnings, and flake check passed on x86_64-linux. check/status are now
available. Node 4 is committed by the user, and all 29 committed source files
match its tested snapshot. Its pre-commit 86 cases, build and flake check passed
on x86_64-linux. The project worktree was clean at transition. Node 5 is now
committed by the user. All 33 committed files match its tested snapshot; the
project worktree was clean at transition to node 6. Node 6 is committed by the
user and all 36 committed files match its tested snapshot. The project worktree
was clean at transition to node 7. Node 7 is committed by the user; all 38
committed files match its final snapshot, including CHANGELOG. The project
worktree was clean at transition. Node 8 is implemented and verified in the
project history, confirmed against all 40 verified files. The project worktree
was clean at transition. Node 9 is committed and confirmed against its 42-file
verified source snapshot, with all 177 cases passing. Node 10 implements read-only
discard preview, committed and confirmed against its 45-file snapshot, with all
195 cases and final format/build/flake checks passing. Node 11 is committed by
the user; all 45 committed files match its verified snapshot, with 216 cases
and final format/build/flake checks passing. The project was clean at transition.
Node 12 (non-cascading Node deletion) now has application/CLI code, README and
a dedicated Cabal test suite written. The user ran `nix flake check`: compilation
succeeded and 10 of 11 suites passed. Four deletion matrix cases failed because
their fixture incorrectly used Content as a Checkpoint main parent. The fixture
now keeps Root as first parent and its Content chain as second-parent history;
new unused-result/shadowing/redundant-pattern warnings were also corrected.
The user reran `nix flake check` successfully on x86_64-linux. Read-only build-log
inspection confirms all 11 suites and 240 cases pass, including 24 deletion cases;
the derivation is /nix/store/qg2myym4mngk5xlrzy5z36sihyjraxg8-git-roam-0.1.0.drv.
The user staged the six implementation/test/README files. Staged review and
diff --cached --check passed. The user subsequently explicitly requested fixing
the missing deletion CHANGELOG checkbox and drafting the message against the
entire diff without staging. The checkbox is now checked and TODO 0.1.0 is
unchanged. The user committed the intended seven-file change as
`feat(git-roam): add confirmed non-cascading Node deletion`; read-only inspection
confirms that change and a clean project worktree. Prior successful checks predate
the one-character documentation update. No new build/check was performed merely
to duplicate the user's verification.
Deletion requires an explicit UUID and preview-bound confirmation;
all other retained historical incoming edges and any target checkout block it.
The implementation uses one expected-old deletion plus verifies for other managed
refs, full candidate/result validation and exact reviewed local config cleanup.
Cleanup is separate from ref deletion; failures report actual refs without rollback.
The milestone-12 helper/snapshot under tmp/ predates the user's final check;
do not mistake it for the tested source. Verification came from the user's
ordinary Git-source flake check. Further agent build/format/check executions
still need explicit authorization. Minimum Git/other platforms remain untested.
Node 13's verified public-CLI end-to-end suite and expanded README tutorial,
synchronization and diagnostic/compatibility boundaries are now committed by
the user as `test(git-roam): verify the standard Git lifecycle end to end`.
Read-only comparison confirms all 48 committed files match the final verified
snapshot; the project worktree is clean. Nodes 0 through 13 are complete and
user-committed. The current standard-Git implementation batch is finished.
Four matrix cases cover SHA-1/SHA-256 and files/reftable, CLI Node creation and
exact old dependencies, push to local bare remotes, clone/fetch/deploy/tracking, unsafe and safe native FF,
native complete multi-ref updates under the ordinary Hook, discard, deletion,
full undeploy and disable. The 48-file milestone-13 snapshot/helper is prepared
under tmp/; prior milestone snapshots are untouched. The user authorized on-demand
repetition of root 120s formatter, milestone-13 snapshot 240s build and 120s flake
check. The first build passed all 244 cases / 12 suites with the four full CLI
lifecycle cases. Documentation review then added explicit local bare-remote push
coverage; the final source also passed all 244 cases / 12 suites (check phase
2m16s), then its flake check passed. The final treefmt check processed all 46
eligible files with zero changes. Only the inherited Undeployment.hs unused
import warning was observed; no new warnings. The standard-Git loop is accepted
on the pinned x86_64-linux environment; minimum Git and other systems are not.
The acceptance commit has three project changes: README.org, cabal/git-roam.cabal and the
new cabal/test/EndToEnd.hs. No production code, lockfile or protection config
changes were needed. CHANGELOG's current-batch boxes were already completed by
node 12 and remain unchanged, as does TODO 0.1.0. No release/tag is implied.
Final derivation: /nix/store/isbwc7vsz74h5m83rman5labsbqzs73m-git-roam-0.1.0.drv.
All 48 committed/current/snapshot files match manifest SHA-256
f791412a9a958b339d3293f33b25c611378ee87c240941688429919be37601db.
Snapshot/helper: tmp/git-roam-milestone13-source/ and
tmp/prepare-milestone13-source.py. Tests originally used uncommitted source;
post-commit read-only blob comparison now grounds the completed state in the
exact committed snapshot. This is source equivalence verification, not a new
post-commit test run or retrospective provenance for earlier test sessions.
Ordinary test work has no independent archival requirement.

## Navigation and authority

- [design.md](design.md): effective v0.1.0 knowledge-dependency protocol,
  Content/Checkpoint encoding/projection, managed closure and lifecycle.
- [context-checkpoint-direction.md](context-checkpoint-direction.md): the agreed
  v0.2.0 context-Checkpoint protocol, its constraints and rationale, the
  isolated V2 implementations, and the A/B/C cutover strategy; the product
  protocol stays v0.1.0 until that cutover.
- [implementation.md](implementation.md): accepted historical implementation plan,
  experiment gate, serial
  project commits, execution defaults, validation and authorization boundaries.
- [object-reader-performance.md](object-reader-performance.md): completed isolated
  full-validator performance comparison, resource budgets, raw evidence and limits.
- [native-git-validation.md](native-git-validation.md): actual standard-Git results,
  native failure hazards, verified adapter choices and the independent archive.
- [experiment.md](experiment.md): completed independent batch-patch experiment,
  evidence limits and historical approvals, not the current task's instructions.
- [Independent experiment manifest](../archive/2026-10-31T06-58-49Z--worktree-batch-experiment/MANIFEST.md):
  immutable selected local experiment inputs/results.

The project skill routes here. GAW's own workflow and product Checkpoints are
different concepts. The final user decisions supersede conflicting assumptions
from the original design ZIP. Current memory is not a reconstruction of proposals.

## Adopted design changes needed for recovery

These record the v0.1.0 model; the v0.2.0 successor is recorded in the
phase-one section below and in
[context-checkpoint-direction.md](context-checkpoint-direction.md).

- Formal versions have complete direct dependencies and possibly multiple
  same-Node formal predecessors. Content does not have a formal dependency set.
- Extra same-UUID Checkpoint parents retain formal history; external UUID parents
  encode exact dependencies. Protect all existing formal Checkpoints by default,
  not just externally referenced ones or a first-parent anchor.
- Native legal progression may add Checkpoints. Explicit discard removes
  exactly the minimal formal successor closure, subject to one-branch
  representability; affected tips become the unique remaining maximum or Root.
- Normal dependency closure requires persistent local Node branches retaining
  the required formal versions. Object reachability alone is insufficient.
- Enable/disable control protection independently of worktrees. Enable accepts
  any knowledge-history state; disable requires full linked-worktree undeploy.
- Node create --path creates both identity/branch and worktree. Full deploy may
  create missing local tracking branches from fetched canonical remote candidates
  but never advances existing local branches. There is no independent adopt.
- Full undeploy covers all Node linked worktrees, including user-created/moved
  ones. Main and detached worktrees have the separate boundaries in design.md.
- No CSV, directory-classification registry, remembered deployment root, partial
  deploy or historical checkout. The eight-character UUID hash naming is fixed.
- When tip is a Checkpoint, create a new same-tree Content before a new Checkpoint;
  do not reuse the old second parent. Complete dependency inheritance is only a
  construction convenience.
- Execution mechanisms, Git compatibility and concurrency remain to be tested.
  Validated Haskell plans do not freeze external Git state or prove isolation.

## Actual repository baseline

The committed project includes the roadmap and node-1 foundations:
GitRoam.Cli/Git/ObjectId/Repository and private BuildInfo, using
async/process byte pipes, text, transformers and build-time Git executable lookup.
The executable prints help/version or usage errors. Cabal declares 12 unit cases
and nine Git/CLI integration cases, all passed. Nix selects ordinary git using
GIT_ROAM_GIT at compile time and keeps doCheck enabled. Version is still 0.1.0;
locked inputs and declared x86_64-linux/aarch64-linux/aarch64-darwin are unchanged.
No patched Git is integrated.

The committed baseline also includes node-2 Protocol.Identity/Objects/History,
its 36 protocol cases and README, plus committed node-3 inspection and 79 tests.
Protection lifecycle, worktree deployment/removal, Node creation, Checkpoint
creation and confirmed discard are now committed through node 11. Their later
verification sections below supersede the earlier milestone descriptions.

README.org retains the user's title/author, records that v0.1.0 is finalized and
tagged, documents the implemented help/version and inspection interfaces,
build/check commands, native Git selection and tests, and outlines the planned
v0.2.0 direction without claiming an implemented interface. The committed
CHANGELOG.org preserves its canonical Org header, records `DONE v0.1.0` with its
UTC `CLOSED` time, and carries a `TODO v0.2.0` development checklist.
Implemented and verified capabilities are checked through node 13, and after that
batch the user committed five further capability changes plus one test-fixture
fix (see "Post-node-13 capability changes" below): explicit `node create --id`
with bundle reporting and Nil/Max admission, selectable text/JSON/CBOR creation
output, a PATH-resolved protection Hook with legacy-command migration, and
deployment into a shared root with unrelated tracked content. At that point the
project tree held 52 files and Cabal declared 14 test suites (288 cases in that
build); later counts are recorded in the v0.2.0 sections. Optional naming and
acceleration candidates remain separate from the current batch. No
no-op/scaffolding claims are included.

## Verification and provenance limits

Earlier skeleton build/flake checks passed on x86_64-linux with GHC 9.10.3, before
or around the user's README correction; those are not fresh checks of every
later tree. Other declared platforms were not thereby validated. The formal
design consolidation is supported by user decisions and current small-file
inspection, not by a new protocol implementation or native-Git experiment.

For the current CHANGELOG worktree, timeout 120s nix fmt --no-write-lock-file
completed and changed only CHANGELOG.org's Org spacing. Then timeout 120s nix
build --no-link --no-write-lock-file -L path:.#default succeeded (exit 0; this
does not establish a fresh compile or new product tests). Its first sandboxed
attempt could not access the Nix daemon; the same authorized command succeeded
with host access. No other platform was built.

The original path:. check failed in treefmt when the copied GAW Hook could not
find git-gaw. After separate user authorization, timeout 120s nix flake check
--no-write-lock-file -L . passed on the clean committed roadmap. Nix reported
zero checks requiring execution and omitted both other platforms. Do not disable
protection or reintroduce .git metadata into check source. Future untracked source
files require an explicit clean snapshot strategy or user staging.

The completed independent reproduction remains separately archived. Its source-
pinned 2.54 and nixpkgs-patched 2.56 no-checkout results do not establish product
protocol, Hook, real checkout or minimum-Git support. The new separate standard-Git
experiment is now executed and independently archived; follow its dedicated memory.

The earlier design/planning and pre-commit validation checkpoints had no new
project parent: the semantic decisions were user-supplied and the validation
used an uncommitted worktree. The roadmap phase transition was grounded in its
exact committed tree and staged-blob match. The corrected root check now genuinely
ran against that clean committed snapshot; the native experiment still uses
independent fixtures and does not validate application code. Keep these distinct
when selecting project parents for the combined verification state.

## Node-1 verification and handoff

The user authorized on-demand repetition of the root formatter and the following
clean-snapshot build/check for this node. All completed with exit 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone1-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone1-source

GHC 9.12.3 built the final implementation. Both test suites passed (12 unit and nine
integration cases). The fresh treefmt check reported zero changes; other declared
platforms were omitted. A subsequent user review removed the initial Nix preCheck
workaround and GIT_ROAM_TEST_EXECUTABLE override. Tests now use only the internal
Cabal build-tool-depends declaration and findExecutable/makeAbsolute, following
the inspected GAW test organization. No test binary path is hard-coded in Nix.

The lookup failure was reproduced with the GHC-bundled Cabal 3.12.1.0: its
component graph correctly includes and builds exe:git-roam before the adapter
tests, but Setup test does not expose it on the test process PATH. Selecting
haskellPackages.Cabal_3_14_2_0 in setupHaskellDepends first made the same tests
pass without executable-path injection. Further comparison identified GAW's
explicit final_.haskell.packages.ghc912 selection in its package overlay, absent
from Git Roam's original default-package-set overlay.

The user then explicitly requested following GAW. The final Git Roam overlay now
selects final_.haskell.packages.ghc912, and the independent setupHaskellDepends
override has been removed. The actual build reports GHC 9.12.3 and bundled
Cabal 3.14.2.0. All 21 cases and flake check passed again on x86_64-linux.
The Cabal file remains the sole declaration of test suites and the internal tool
dependency. README documents the GHC 9.12 package set. No lockfile change, custom
Setup script or test-path injection is present. The earlier Cabal-only selection
is superseded, not the final implementation. These observations do not establish
the earliest fixed Cabal release or the exact installed GAW derivation's toolchain.

The clean snapshot contains 20 explicitly enumerated files, including eight new
untracked Haskell files, and excludes .git/.agents/unrelated ignored content.
Final read-only comparison confirmed every project and copied file matches the
tested manifest. Manifest SHA-256:
a065e194a154f5593133d28b7574759f5a621882efe7aa29e33a282e66fd2929.
The final staged review passed diff --cached --check. The user subsequently
committed that exact source snapshot; CHANGELOG and lock inputs were unchanged.
The successful package derivation is
/nix/store/cdnkq15g50y09qyzzkzvc6brz02hzb34-git-roam-0.1.0.drv.
The tests originally ran on an uncommitted snapshot. After the user committed it,
all 20 committed files were directly compared with the tested manifest and match.
That observed committed baseline now supplies provenance for the node-2 transition;
no claim of fresh post-commit test execution is implied.

## Node-2 implementation and verification

New modules GitRoam.Protocol.Identity/Objects/History validate decoded native
commit/tree objects through an injectable monadic HistorySource. ValidatedHistory
and ValidatedCommit constructors are private, with non-record accessors. Trees,
commits and parsed identities are memoized by OID, including tree objects shared
by different Nodes. Object lookup/type/incomplete-evidence failures remain
distinct from structural protocol violations. Payload blob bodies are not
interpreted; repository object decoding and complete-store evidence remain node 3.

Implemented canonical UUID labels, one UUID directory and ordinary marker, exact
Root shape, same-Node Content chains, ordered Checkpoint parent roles and exact
tree equality, distinct parent OIDs, same-UUID merge predecessors, one direct
external version per UUID, and consistent Roots over every visited history.
Content and Root do not project to formal versions. Formal projection preserves
H/D/T, formalHistory follows q/M rather than external edges, and combined
knowledge ancestry follows H union D. Empty Content and dependency-only history
are legal; complete dependencies never implicitly inherit. No model change.

The new Cabal protocol-tests suite passes 36 named cases, including 48 generated
graphs over SHA-1/SHA-256, all-pairs combined-ancestry comparisons with an
independent raw-parent traversal, merged formal histories, cross-Node ancestry
traps, malformed/missing evidence, dependency replacement/removal, and memoization.
The existing 12 unit and nine native Git integration cases also pass (57 total).
Initial tests passed but compiler warnings prompted local name/type cleanup;
shared-subtree caching and additional semantic cases were then verified again.
The final build emitted no compiler warnings. README describes the implemented
library and later CLI/object-loading boundary. CHANGELOG stays unchanged: its
user-facing feature boxes are not completed by this internal protocol layer.

The user separately authorized on-demand repetition, in order, of these exact
commands for node 2, all now passed with exit 0 on x86_64-linux:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone2-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone2-source

Build uses GHC 9.12.3 and Cabal 3.14.2.0; the fresh formatting check reported no
changes. aarch64-linux/aarch64-darwin were omitted. No lockfile change was needed;
containers is declared in Cabal for maps/sets. The final package derivation is
/nix/store/m09c2n1paqrz65q4iz9dpfmrbqspgkgc-git-roam-0.1.0.drv.
All 24 source files match the tested clean snapshot. Its manifest SHA-256 is
996a9b883a838002f2f68b99906173a61ed374fd2610ae8ad5489759816b0463.
The bounded helper and snapshot are tmp/prepare-milestone2-source.py and
tmp/git-roam-milestone2-source/, separate from node 1. The user staged and committed
node 2. All 24 committed files match the tested snapshot; the worktree is clean.
The pre-commit tests were not rerun merely to create provenance. This direct
committed-source comparison grounds the node-3 transition in the actual baseline.

## Node-3 implementation and verification

GitRoam.Git.Objects decodes stored commit headers and binary tree entries through
cat-file --batch for SHA-1/SHA-256. Per-call inspection uses --no-replace-objects,
GIT_NO_LAZY_FETCH=1, GIT_OPTIONAL_LOCKS=0 and GIT_GRAFT_FILE=/dev/null. The latter
keeps rev-list connectivity aligned with raw stored parents: an integration case
confirms a graft cannot hide a missing older marker blob. No payload bodies are
needed for protocol interpretation; rev-list --objects --missing=print checks
reachable object evidence, while shallow repositories report incomplete history.
The Git source identifies GIT_GRAFT_FILE in environment.h; native fixture behavior
is the verification basis, not a claim about an untested Git release.

Protocol.Repository provides private ManagedState, validation of branch UUID/tip
identity and every retained Checkpoint's dependency branch/version membership,
and a pure Root/formal-history preservation relation between validated states.
The relation rejects existing branch removal, Root changes and loss of any old K,
while allowing non-FF replacement of unconfirmed Content. Creation authorization
and realtime enforcement still belong to node 4; this pure relation alone does
not grant ordinary Git permission to create managed branches.

Application.Inspect shares these functions between public check/status and later
operations. It enumerates only canonical local UUID heads as managed candidates,
keeps symbolic targets in before/after observations, diagnoses unsupported Node
symbolic refs, and does not silently drop broken-ref warnings. Explicit Node scope
expands to the persistent branches required by all of that Node's retained formal
history; unrelated malformed histories need not block that selected scope.
Repository scope checks every managed Node. Required missing branches differ from
present branches lacking the required formal version. Old and same-UUID merged
formal history dependencies are included, not only the latest/first-parent path.

CLI exposes check/status [--node <uuid>]. Without --node it infers an actual Node
worktree, otherwise falls back to repository scope. Read-only commands need no
enabled protection. Status shows Root/Content/Checkpoint tip, latest K, unconfirmed
Content, formal count, exact dependencies and actual Git-recorded worktree paths.
Content dependencies are explicitly labelled as the latest K's, not Content's own;
no Checkpoint means no formal declaration. Main, linked/moved and detached records
are distinguished. No deployment registration or Node lifecycle is introduced.

Exit codes: 0 successful; 1 protocol/management violation; 2 argument error;
3 unavailable evidence, Git read failure or refs changing during observation.
Before/after comparison also runs after an unsuccessful history/state inspection;
a changed observation takes precedence over a transient closure diagnosis. It
does not provide a global atomic snapshot or arbitrary-writer serializability.
Neither inspection nor failure diagnosis repairs refs/history/worktrees.

Cabal inspection-tests passed 22 cases, including real native histories for both
files/reftable and SHA-1/SHA-256, raw decoders, identity/Root conflicts, historical
and merged dependency closure, scope, missing blobs/commits, replace/grafts/shallow,
dirty-index/file/ref preservation, main/moved/detached and bare worktrees, symbolic
refs, changing observations, native Content retention and actual CLI diagnostics.
The existing 36 protocol, 12 unit and nine adapter cases also pass: 79 total.
Final build has no compiler warnings. Initial success was followed by an unused-
import cleanup, stronger actual CLI failure assertions and stored-history checks.

The user separately authorized on-demand repetition, in order, of these exact
commands for node 3, each now passed with exit 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone3-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone3-source

GHC 9.12.3/Cabal 3.14.2.0, standard Git 2.56.0, x86_64-linux; aarch64-linux and
aarch64-darwin were omitted. No lockfile or Nix packaging changes. Final derivation:
/nix/store/3csvw0wmgh74kfngr3y6jm09rygs5fj8-git-roam-0.1.0.drv.
All 28 project/snapshot source files match manifest SHA-256
f9f42c24320bb8cbfc6e673a2f6ef90ce7f35a667d754fd6954817217e86292d.
The bounded helper and snapshot use tmp/prepare-milestone3-source.py and
tmp/git-roam-milestone3-source/, preserving earlier snapshots. diff --check passes
and the staged candidate matches all 28 verified source files. README describes current commands and boundaries.
At the committed node-3 baseline, CHANGELOG remains TODO 0.1.0 and marks only
inspection/status complete. The user subsequently committed the exact tested
source; all 28 committed files were directly matched to the manifest before
node 4. No fresh post-commit test execution is implied by that comparison.

## Node-4 implementation and verification

Application.Protection implements enable/disable, exact local/effective named
Hook health, common-directory operation locking, the private reference-transaction
entry and ownHookBypass. Configuration names are restricted to
hook.git-roam-reference-transaction.{event,command,enabled}. The command shell-
quotes this actual executable's absolute path. Enable is idempotent when matching,
accepts invalid knowledge history, and refuses inherited/incomplete/divergent
own-name configuration. Other hooks are never globally disabled or overwritten.
The version floor is Git 2.54; full minimum-version compatibility remains unproved.
Later, see the post-node-13 section: the Hook command became the PATH-resolved
`git-roam --reference-transaction` with legacy-command migration, replacing the
store-absolute path described here.

Disable is idempotent when absent, removes only matching local own-name keys,
and refuses any remaining canonical Node linked worktree, including user-created
ones. It neither removes/switches main worktrees nor deletes refs/objects. Public
deploy/undeploy remain later nodes, so manual native worktree cleanup may currently
be required. Configuration uses native Git locking and sequential writes, not an
atomic multi-key install guarantee; failed/incomplete configuration is diagnosed
rather than automatically overwritten or guessed back into place. Enabled
configuration is bound to the matching executable; an upgrade/different path
requires explicit lifecycle/configuration review.

withOperationLock atomically creates git-roam.operation.lock in the common Git
directory, refuses a busy/unavailable lock and never removes a preexisting lock.
Its own acquired directory is released after the operation. Common-directory
filesystem encoding failures are explicit refusals, not lossy path writes.
requireProtection is the health prerequisite for future mutating application
operations. ownHookBypass supplies only a per-call named enabled=false setting;
controlled ref writes must independently validate and use expected-old updates.
No public Node mutation is introduced in this milestone.

Git 2.56 sends preparing before prepared. Initial matrix tests failed because the
private CLI omitted preparing; this was corrected. Preparing, committed and aborted
are accepted no-ops, with actual rejection checks in prepared. The input's old OID
is not used to infer branch existence: actual managed refs are read while targets
are prepared. HEAD and noncanonical/non-managed refs are ignored. Ordinary new
managed branches, deletion and Checkpoint discard are refused. Existing no-op and
legal Content changes can pass. Local history checks compare Root and complete
formal sets, with raw object connectivity, avoiding unconditional full repository
history scans on Content-only transitions. Formal changes validate both complete
before/candidate managed sets and the shared formal-preservation relation.
The complete multi-ref transaction is evaluated together, not row by row.

Application.Inspect now exports validateCandidate for a caller-supplied final ref
set, sharing the protocol and managed-state validators and checking reachable
objects without writing refs. Candidate validation is not itself authorization,
an expected-old check, a live atomic snapshot or arbitrary-writer isolation.
Native prepared-phase locks and the common-directory application lock narrow
races; they do not promise a global transaction across arbitrary external actors.

Tests retain the 79 previous cases and add seven protection groups: lifecycle on
invalid history/repeated calls/config conflict/busy-lock preservation, refusal to
disable with manual linked worktrees, own-only bypass with another rejecting Hook,
and native protection for files/reftable x SHA-1/SHA-256. Real Git exercises
Content creation, non-FF Content replacement, commit/amend/soft-reset, native
Checkpoint progression, marker/tree corruption rejection, ordinary create/delete/
discard rejection (including a Root-only Node), and a joint two-ref update whose
new dependency closes only in the final set. Total 86 cases pass; final compiler
output has no warnings. An initial test do-block compile error was also corrected.

The user separately authorized repeating these exact commands in order for node 4,
each timeout 120s; all final commands passed with exit 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone4-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone4-source

The build uses GHC 9.12.3/Cabal 3.14.2.0 and standard Git 2.56.0 on x86_64-linux;
the other declared platforms were omitted. Final package derivation:
/nix/store/cmw0i05x9lzr6cd2502ykm1a2ga2k7x8-git-roam-0.1.0.drv.
All 29 files match manifest SHA-256
f1d566e5bb658e2cbe932ea51c4581bc55ce64ab68cbdac3644069893d268015.
tmp/prepare-milestone4-source.py and tmp/git-roam-milestone4-source/ preserve older
snapshots. diff --cached --check passes; the staged index matches all 29 verified
source files. No lockfile changes.
README records actual lifecycle/safety/compatibility limits. CHANGELOG remains
TODO 0.1.0 and additionally checks the two repository protection boxes. History-
constructing/deploy/delete/discard application capabilities remain unchecked.
Only temporary fixture repositories installed/disabled Git-roam protection; the
actual project still has its canonical GAW Hook and no Git-roam installation.
These tests concern uncommitted node-4 source, so no new project parent is added
to the final handoff checkpoint.

## Node-5 implementation and verification

The user committed node 4; all 29 committed source files were confirmed equal to
its tested snapshot before node 5. The new internal worktree foundation uses a
shared binary NUL parser, including raw filesystem paths, unborn/bare/main/
detached state and locked/prunable diagnostics. Inspection and disable now reuse
that parser. Deployment/removal plans have private constructors and require a
repository-wide validated managed state. Fixed short names follow the accepted
SHA-256/first-five-bytes/Base32 algorithm; collisions are explicit failures.

Planning preserves manual/moved deployments, rejects main checkout conflicts,
occupied targets and symlink path components, and checks nested roots against
the outer Git repository's ignore and tracked paths. No deployment registry is
introduced. Later, see the post-node-13 section: the outer-root check became
index-based (`checkOuterTargets`) and no longer requires ignore rules. Removal
preflights all targets, protecting staged/unstaged/untracked/
ignored files, empty unknown directories, special files, unfinished operations,
locked/prunable worktrees, assume-unchanged/skip-worktree entries and submodules.
Selected nested Node worktrees are removed deepest first; non-target nested
worktrees prevent removal. Main worktrees are reported, never removed.

Protected native add/remove primitives require matching enabled protection and
the common-directory operation lock, recheck plans, disable only their own named
Hook for independently checked calls, and verify the resulting refs/registration.
They do not create/delete Node branches. Add disables remote guessing. Execution
uses the common Git directory so removing the caller's linked directory does not
invalidate later Git calls. A failed native operation may leave residual state;
there is no force cleanup, automatic rollback or filesystem atomicity claim.
Public deploy/undeploy/node-create commands remain later milestones.

Fifteen new test groups cover naming/parser/path safety, nested ignore protection,
manual/moved dirty worktrees, user-data and index-flag refusal, stale plans,
nested removal, main/locked/prunable states, other-Hook failure residuals, and
protected primitives across files/reftable x SHA-1/SHA-256. Together with the prior
86 cases, Cabal declares 101 cases. The Nix package keeps doCheck=true.

The user authorized on-demand repetition of these exact commands for node 5;
all completed with exit 0, in this order:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone5-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone5-source

The user reported already running formatting and flake check. Our formatting
changed zero files; build/check reused cached results, with no fresh compiler or
individual test output. This validates the matching derivations, not a fresh test
run. Package derivation:
/nix/store/cdwmxb6zy2mbdhd5skhk1mzv1nza64j2-git-roam-0.1.0.drv.
Only x86_64-linux was checked; aarch64-linux/aarch64-darwin were omitted.
All 33 current worktree, clean snapshot and user-staged index files match manifest
SHA-256 dfe37b54765889937f0b531133e853262f2b4c3d7d69cfbafb542b4032c8e6c8.
The bounded helper is tmp/prepare-milestone5-source.py; older snapshots remain.
Staged diff --check passes. README describes the internal capability and limits.
CHANGELOG stays TODO 0.1.0, with no deployment box checked before public commands.
No project protection installation or project staging/commit was performed by
the agent. This uncommitted source is not represented by an added project parent.

## Node-6 implementation and verification

The user committed node 5 and explicitly requested continuation. All 33 committed
source files match its tested snapshot. Application.Deploy now implements public
deploy --path <path> [--remote <remote>]. All local canonical UUID branches take
priority and are never advanced; canonical fetched candidates establish missing
local branches. Equal-OID sources coalesce deterministically; different tips
refuse automatic selection, regardless of checkout.defaultRemote. --remote limits
discovery of missing Nodes to that configured remote, without excluding locals.

The complete target is validated before writes, permitting incomplete initial
branch closure to become complete. Paths are preflighted against current refs and
the validated target without temporarily installing branches. Native update-ref
creates the missing set jointly, verifies existing and source refs, then native
branch --set-upstream-to configures tracking and worktree add checks out existing
local branches with guessing disabled. No fetch/adopt/merge or existing-worktree
relocation is performed. Existing local configuration for a missing branch refuses
creation. Main checkout conflicts refuse deployment. Relative --path resolves
against the invocation directory, including ignored nested roots.

On failure, compensation only attempts issued new worktree additions at unchanged
planned tips. Branch rollback requires a confirmed successful creation transaction,
unchanged tips/configuration, no checkout, and a closed final ref set. The closure
fixed point preserves every dependency required by retained histories, including
old Checkpoints. Changed/unsafe or externally created state is kept and reported.
Final refs and closure are checked, with no filesystem atomicity or arbitrary
external-writer isolation promise. IOException or unavailable evidence produces
explicit failure/inspection guidance rather than guessed cleanup.

The first build compiled, but a race fixture was blocked by the application lock
before its intended expected-old test. The corrected fixture models an explicitly
uncoordinated writer using only its own temporary repository's Hook bypass. Test
compiler warnings were also cleaned up. Review required an execution journal so
compensation never removes a competing same-OID creation; a regression covers it.
The final source passes all 117 cases without compiler warnings: 16 new deployment
groups plus the previous 101, using shared Cabal fixture helpers. Coverage includes
actual local clone/fetch, native tracking, files/reftable x SHA-1/SHA-256, ambiguity,
incomplete-to-complete closure, unchanged locals, clean/dirty failure compensation,
stale expected-old checks and competing branch creation. Only fixtures install
Git-roam protection or mutate history; the actual project's GAW Hook is unchanged.

The user separately authorized repeating these exact node-6 commands in order;
all final commands passed with exit 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone6-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone6-source

The final build reused the successful compiled/tested package after documentation
updates; flake check ran the final treefmt check, with zero formatting changes.
Package derivation: /nix/store/sv0b4104s6nad85fzld11v9ld188sp6w-git-roam-0.1.0.drv.
Git 2.56.0, GHC 9.12.3/Cabal 3.14.2.0, x86_64-linux only; other declared platforms
remain unverified. The 36 worktree and clean-snapshot files match manifest SHA-256
26519c9c3c589d62e4f143338b5aa9b5c3bded6e144d80f033cef6365fc38385.
Snapshot helper: tmp/prepare-milestone6-source.py. diff --check passes; the user
staged node 6 and all 36 index/worktree files match the verified snapshot. No
lockfile changes. README describes actual deployment usage and
failure limits. CHANGELOG remains TODO 0.1.0 and checks four deployment-related
items, leaving full undeploy unchecked. No project parent represents this as-yet
uncommitted implementation; do not attach its baseline as though tests ran there.

## Node-7 implementation and user verification

The user committed node 6; its 36 committed files matched the tested snapshot
before new edits. Application.Undeploy now exposes full undeploy with enabled
matching protection, shared complete-history validation and whole-target safety
preflight. Native removals run deepest first and stop on failure. Linked Node
worktrees include manually created/moved ones. Main Node worktrees are reported
and retained; detached and ordinary worktrees stay outside the removal set.
Refs, objects, tracking and protection configuration are retained. Partial failure
reports confirmed removals and available actual remaining state, without recreating
worktrees or resetting user changes. Absolute path checks avoid getcwd so commands
can continue after the invocation worktree has been removed.

Seventeen new Cabal test groups bring the declared total to 134. They cover
files/reftable x SHA-1/SHA-256, whole-input dirty/ignored/locked refusal, main and
non-target boundaries, nested CLI invocation from a removed directory, native
failure, lost completion, late user edits, changed refs, invalid history and
empty/repeated operation. README documents actual usage and execution limits.

The user initially staged the unformatted source and requested a message. Static
review found a coherent staged change; the draft was written with the explicit
warning that validation had not occurred. The pending request for agent-executed
node-7 format/build/check commands was not answered. Instead the user supplied
their actual shell results: initial nix flake check failed treefmt; nix fmt then
formatted six files, changing four; subsequent nix flake check passed (exit 0,
55.97s), building both package and formatting check; nix build passed (exit 0,
1.46s, reusing the result). Package derivation:
/nix/store/q7niv55lf451lnqg6ps3f07wdk2vihn3-git-roam-0.1.0.drv.
These are user-executed verification results, not agent-executed tests or new
authorization. Individual test logs/compiler warnings were not provided; the
package's doCheck=true and successful flake package check cover its Cabal tests.
Only x86_64-linux was checked; other declared platforms remain unverified.

Read-only inspection confirmed the formatted implementation and README were
already restaged with no unstaged project changes. After that verification, only
the undeploy checkbox was checked in CHANGELOG, retaining TODO 0.1.0. This one-line
progress update has not been included in a new build/check run. All 38 current
worktree/source-snapshot files match manifest SHA-256
f152231d31c36a02610c0cd96dc5f2222368731f38ccb1ce5c6dc3af893189d9;
all 37 files other than that new CHANGELOG edit match the index. The bounded helper
is tmp/prepare-milestone7-source.py, with earlier snapshots preserved. The user
needs to stage CHANGELOG. The existing commit message remains semantically valid:
feat(git-roam): add full Node worktree undeployment. No project parent represents
this uncommitted source; do not attach a baseline as though it was tested.

## Node-8 implementation and verification

The user committed node 7 and requested continuation if it matched expectations.
All 38 committed files, including the final CHANGELOG checkbox, matched its source
snapshot before new edits. Application.Create now implements node create --path:
UUIDv4, empty-marker parentless Root, persistent local UUID branch and immediately
editable linked worktree. It reports UUID, Root OID and actual short-name path.
Extended after node 13 with an explicit `--id`, the bundle path and text/JSON/CBOR
output; see the post-node-13 section.
Only the new Node is deployed; other undeployed Nodes are not implicitly deployed.
Internal plans carry an explicit operation target set: full deploy still targets
all Nodes, while creation targets only the new one. Review found the original
reuse of full-deploy planning incorrectly refused unrelated main/locked worktrees;
that restriction is corrected and covered by two additional regression groups.
Valid existing linked directories are still recognized for deployment-root reuse.

Cabal adds uuid for UUIDv4 generation, selected from locked nixpkgs (1.3.16.1 in
this build). The library accepts an injected identity generator for deterministic
collision tests, but the CLI exposes no user-selected UUID. New identities must
have v4/variant bits; historical identity parsing is unchanged. Superseded after
node 13: `--id` accepts a UUIDv4, Nil UUID or Max UUID, while default generation
remains UUIDv4. Current managed
history must be valid. Local/fetched/tag/configuration or unborn-checkout identity conflicts, path
conflicts and native author/committer availability are checked before object writes.
Native hash-object, mktree and commit-tree construct exactly <uuid>/.roam with a
zero-byte regular marker and no parents, without using the caller's index.
The complete target is validated before conditional creation; existing refs are
verified in the transaction, then the protected worktree primitive performs add.
Git identity configuration remains authoritative. No tracking is invented for a
brand-new identity and no existing Node history is advanced.

Creation records confirmed ref establishment and issued worktree calls, validates
the actual result, and compensates only proven new unchanged safe state. Dirty
worktrees, changed Content history, changed branch configuration, competing same-
OID results and uncertain observations are retained/reported. Deletion requires
an unchanged unchecked-out Root branch and validated remaining closure, with
expected-old checks. Objects are never manually deleted; failed attempts can leave
unreachable objects or an empty deployment parent. Other hooks remain active.

The 19 new creation groups cover both backends/formats, Root tree/parents/marker,
generation bits, native editing, only-new-Node deployment, UUID/ref/configuration
and path conflicts, missing author/committer, clean/dirty failures, changed Content,
competing same-OID creation, stale existing refs, existing main/locked worktrees,
unborn checkout conflicts and the actual CLI local loop.
All 153 cases pass in the final successful build. The first variant compiled uncached uuid
dependencies and passed 134 cases before timeout 120s during undeployment-tests.
The agent stopped and reported it; the user separately authorized the exact same
120s build command again, which passed. No timeout expansion or silent retry.
An inherited unused-import warning in Undeployment.hs and dependency warnings were
observed; no claim of warning-free compilation. No unrelated cleanup was applied.

The user authorized on-demand repetition of these exact node-8 commands, and
separately reconfirmed the build after timeout; all final commands exited 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone8-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone8-source

Final package derivation: /nix/store/s8kxb3i8ly2qhh518s44adxc5hhj5av2-git-roam-0.1.0.drv.
The final package build reused the successful 153-case result after the last README
clarification, and the final flake treefmt check passed with zero changes.
Git 2.56.0, GHC 9.12.3/Cabal 3.14.2.0, x86_64-linux; other declared platforms were
omitted. All 40 current worktree/source-snapshot files match manifest SHA-256
a0e5664d93049510076d8c4699607c6be6a85628b159be193849f7bade644e41.
The helper is tmp/prepare-milestone8-source.py. diff --check passes; the user staged
the change, and all 40 index/worktree files match the verified source snapshot.
No lockfile changes or project Hook installation. README records
the create/edit loop and failure boundaries. CHANGELOG remains TODO 0.1.0 and now
checks Node creation and ordinary Content editing. These tests used uncommitted
source, so no additional project parent represents their snapshot.

## Node-9 implementation and verification

The user committed node 8; all 40 committed files matched the verified snapshot
before new edits. Application.Checkpoint now implements checkpoint [--node UUID]
(-m text|-F file), with repeatable --depend revision, --drop-dependency UUID and
--clear-dependencies. Selection is explicit or inferred from a legitimate Node
worktree, never from the number of branches. Root requires prior Content. A Content
tip is retained as w; a Checkpoint tip gets a new same-tree Content object based
on that tip. Only the final branch ref advances once, with expected-old.

Construction inherits the main predecessor's complete direct map (empty before
the first Checkpoint), then clears/removes/adds/replaces it. Each added revision
must resolve unambiguously to a retained external Checkpoint. Root/Content/self,
unretained versions, duplicate UUID inputs, remove-and-replace or clear-and-remove
conflicts refuse before object construction. Exact final dependencies are direct
parents; old declarations remain protected through retained formal history. Formal
merges are not constructed, but existing multi-predecessor histories are preserved.

The tree equals the old tip's committed tree. No write-tree, index snapshot,
squash, working-file inclusion or reused old second parent. Main/linked dirty
state, including exact index bytes, is retained. Native commit-tree uses UTF-8
per call and stdin messages, independent of persistent legacy encoding config.
Messages are nonempty UTF-8/NUL-free text, -F - supports stdin, and no editor or
Conventional Commit requirement is introduced. Shared full candidate/ordinary-
retention validation precedes a transaction verifying other managed refs. Only
the own Hook is bypassed; other Hooks can reject. Post-update state/protection
checks report failure without rollback. Diagnostics identify constructed OIDs,
selected Content, and confirmed versus uncertain ref installation.

The first build failed three cases because GIT_GRAFT_FILE=/dev/null triggered Git
2.56 deprecated-graft advice on successful rev-parse and strict stderr handling
misclassified it. A narrow advice suppression initially passed 172 cases, but the
user subsequently adopted a stronger compatibility boundary: accept Git refs and
unambiguous commit OIDs, not full revision expressions; use native name resolution
but raw objects for knowledge history; remove GIT_GRAFT_FILE and
advice.graftFileDeprecated; introduce no temporary repository view.

The final implementation checks dependency names with native check-ref-format
(or hexadecimal OID syntax), resolves without traversal suffixes, and peels
annotated tags via stored headers. Forced core.warnAmbiguousRefs=true still rejects
ambiguous names even under contrary user config. All three production rev-list
completeness checks were replaced by one shared raw commit/tree traversal and
blob metadata batch-check; gitlinks refer to external databases and are skipped.
Inspection and candidate validation share per-call object caches; shallow refusal
is retained and now explicit in candidate validation and the Hook's local path.
No production revision walks remain. Native commit-tree receives explicit tree
and parent OIDs; deployment/status/ref queries do not derive knowledge ancestry.
An inherited unused-import warning in Undeployment.hs remains; no unrelated cleanup
or warning-free claim.

All 177 cases pass: 23 Checkpoint groups, 30 inspection groups and 124 others. Coverage uses
files/reftable x SHA-1/SHA-256, exact first/second parents and tree, repeated and
empty-diff versions, full dependency inheritance/removal/replacement/clearing,
historical dependency retention, merged formal history, invalid/conflicting and
ambiguous revisions, UTF-8/legacy configuration/file/stdin messages, Root and
selection refusal, dirty main/linked index/files/ignored data, CAS/verify races,
other Hook rejection and post-install read failure without rollback.
The latest cases cover both formats/backends with grafts and replacement refs,
full/abbreviated OIDs, short/full refs, lightweight/nested annotated tags, revision
operator refusal without object/ref writes, missing old blobs in inspection,
candidate validation and native Hook updates, nested trees/symlink blobs/gitlinks,
and shallow candidate refusal. Restoring the missing old blob permits the native
Content update without removing grafts.

The user authorized on-demand repetition of these exact node-9 commands; all
final commands passed with exit 0:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone9-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone9-source

Package derivation: /nix/store/sgyjjps11h7l4sdmfz5vc3xf04lkdd9k-git-roam-0.1.0.drv.
The revised package compiled and ran all 177 tests; final treefmt check passed with
zero changes. Git 2.56.0, GHC 9.12.3/Cabal
3.14.2.0, x86_64-linux only; other declared platforms remain unverified.
All 42 worktree/source-snapshot files match manifest SHA-256
4dbd8d066f39e8894baa2713311a79e6ec88da39f702744edfeb3102249a18d7.
Helper: tmp/prepare-milestone9-source.py. diff --check passes; project index is
empty, no lockfile changes or project protection installation. README and both
Checkpoint/dependency editing CHANGELOG boxes match actual capability; version
stays TODO 0.1.0. This uncommitted tested source has no new project-parent edge.

## Node-10 implementation

The pure Protocol.Discard layer computes the retained Checkpoint successor closure
using projected H/D edges and a per-call reverse graph. It reports exact targets,
formal/dependency collateral reasons and per-Node removed versions. Remaining
unique formal maxima determine candidate tips; empty formal sets use Root and
multiple maxima refuse without enlarging the discard set. Unaffected tips retain
their Content tails. Full candidate validation checks per-Node exact retained
sets and dependency closure. Raw reachable Content set differences report commits
losing managed entry, rather than treating all Content ancestors as deleted.
If no complete candidate is representable, actual Content loss is unavailable.

Application.Discard provides readonly preview without protection prerequisite or
operation-lock writes. It validates initial and candidate states, reuses the
conservative affected-worktree removal preflight, and rereads refs/worktree
registration. Unsafe linked worktrees block; main checkouts are currently reported
as unsupported execution targets, not automatically removed or switched. Unrelated
dirty worktrees do not block. The report is diagnostic data, not a verified mutation
plan or future authorization token. Node 11 must revalidate and bind authorization.

CLI: discard --dry-run <ref-or-oid>..., explicit nonempty targets, duplicate target
OIDs coalesce, shared native refs/OID resolution and raw tag peeling with checkpoint.
No revision expressions. Help advertises only dry-run. Zero means no detected
blocker; one means blocked/invalid/unavailable evidence; two is usage failure.
Blocked reports retain the computed impact on stdout and a failure diagnostic.
No actual discard, force option, confirmation interface or plan ID exists yet.

The 18 new groups cover both formats/backends, linear/multi-target closures,
historical/transitive/non-first-parent dependencies, ambiguous and unique remaining
maxima, Content effects and unaffected tails, refs/tags/OID prefixes, invalid and
unretained targets, incomplete state, dirty/ignored/locked/main worktrees,
unchanged objects/config/index/files, no mutation calls, changing refs and CLI
reporting. Initial compile failures from ambiguous/missing imports were corrected.
The first full build passed all 195 cases; a new test-name shadowing warning was
then corrected. The final source build reran and passed all 195 cases (10 suites),
including the roadmap checkbox and final diagnostic text. Package derivation:
/nix/store/kb5cmw604s7z6q5j8ymx19zb9lsr7y3m-git-roam-0.1.0.drv.
Final formatting and flake check passed, with zero treefmt changes. Git 2.56.0,
GHC 9.12.3/Cabal 3.14.2.0, x86_64-linux only; other declared platforms remain
unverified. The inherited unused import in Undeployment.hs remains outside scope.

All 45 worktree/source-snapshot files match manifest SHA-256
97833580951cb586ee8c830100e8b10dc57d4fa49b4391d24702538194be7ccb.
The bounded helper is tmp/prepare-milestone10-source.py and the snapshot is
tmp/git-roam-milestone10-source/. Previous snapshots are retained. diff --check
passes, the project index is empty, no lockfile changed and no Git-roam protection
was installed in the actual project. README documents the real dry-run interface
and limits; only its CHANGELOG preview box is newly checked. TODO 0.1.0 remains.
Node-10 verification used uncommitted source, so no project-parent edge represents
this tested snapshot. No independent archive is needed for ordinary source work.

## Node-11 implementation and verification

The verified implementation's collect function constructs a
private Plan from shared initial/candidate validation and full worktree preflight.
An unblocked dry run prints a SHA-256 plan ID binding common repository path,
managed refs, Q/S, causal/Content impact and sorted worktree registrations.
Execution uses --confirm <64-lowercase-hex-plan-id>, or terminal stdin/stderr with
full preview and exact ID reply. No force/yes shortcut or persistent plan file.
The protected common-directory session recomputes the ID twice, removes only
confirmed safe affected linked worktrees, verifies all source refs and the expected
registration set, then performs one expected-old/verify transaction. Restoration
uses original paths and actual target tips. Success requires exact final refs,
formal sets, all registrations and matching protection. Any transaction failure
remains a failure even if candidate refs are observed; no formal rollback.
Recovery only recreates confirmed missing worktrees at fully verified original
or candidate refs; other ref sets, occupied paths or uncertain removals are left
for inspection. Actual refs/worktree and transaction-confirmation diagnostics are
returned even for unexpected IO/lock-cleanup failure when context is available.

The worktree layer adds discard-specific safety planning and session-owned
restoration/path checks. Main checkouts, affected parents containing nested
worktrees, private config.worktree or worktree/bisect/rewritten refs refuse.
Outer ignore protection is checked outside the target's own existing worktree,
and rechecked after removal. No automatic forced checkout/cleanup or index reuse.
These are execution support limits, not changes to the permanent DAG model.
The test suite adds 21 execution groups (216 total passing), including files/
reftable x SHA-1/SHA-256, real different-content checkout, partial-removal and ref/
restoration failures, stale/dirty/moved/declined confirmation, transaction response
loss, metadata/nesting refusal and real PTY acceptance/refusal. Cabal declares the
process/unix test dependencies. README and the discard-execution CHANGELOG box
reflect the verified implementation; version status stays TODO 0.1.0.

The user authorized node-11 format/build/check commands on demand, in order:

- timeout 120s nix fmt --no-write-lock-file
- timeout 120s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone11-source#default
- timeout 120s nix flake check --no-write-lock-file -L path:./tmp/git-roam-milestone11-source

The first build rebuilt uncached locked UUID dependencies, compiled the project
and passed 135 existing cases, then reached timeout 120s at discard suite start.
After explicit retry authorization, the second build passed all 39 discard cases,
23 checkpoint cases and those prior 135 cases (197 total), but reached 120s at the
last 19 creation cases. There were no observed test failures. The agent stopped
again and obtained explicit authorization for this new exact command on demand:
`timeout 180s nix build --no-link --no-write-lock-file -L path:./tmp/git-roam-milestone11-source#default`.
Format and flake check retain their 120s authorizations. The first complete 180s
build passed all 216 cases. A new test variable shadowing the imported cwd field
was then renamed. The final 180s build reran all 216 cases (10 suites), passing
with a checkPhase duration of 1m27s. Final format and flake check passed with zero
treefmt changes. The preview explicitly reports fresh worktree administration.
Only the inherited Undeployment.hs unused import warning remains; no unrelated
cleanup. No automatic timeout expansion or retry.

Final package derivation:
/nix/store/h18f30dm7dbpqrpx67cw6c5dlmfmif79-git-roam-0.1.0.drv.
Git 2.56.0, GHC 9.12.3/Cabal 3.14.2.0, x86_64-linux only; other declared systems
and the minimum Git version remain unverified. All 45 worktree/snapshot files
match manifest SHA-256
7b3f1eede2b6bf25f8144ab41a40b4f322472b84fc8149d1658f2fe3dcdc72b2.
Helper: tmp/prepare-milestone11-source.py; snapshot:
tmp/git-roam-milestone11-source/. diff --check passes, the project index is empty,
and no lockfile or actual project protection configuration changed. No project
parent represents this tested uncommitted snapshot; no independent archive is
needed for ordinary source implementation/testing.

## Post-node-13 capability changes

After the node 0-13 batch was accepted, the user requested further changes and
committed them without adding plan nodes. They describe the current product
state; the node sections above are historical and are marked where superseded.

- Explicit `node create --id` was added, and the CLI reports `bundle` (the UUID
directory inside the created worktree) next to node, root and worktree. Default
generation stayed a fresh UUIDv4.
- A later request admitted the Nil UUID and Max UUID as explicit new identities.
`createNodeWith` accepts them alongside the UUIDv4 check and refuses anything
else with "New Node identity must be UUIDv4, Nil UUID or Max UUID". Default
generation is asserted never to produce either extreme. Historical identity
parsing already accepted any canonical lowercase hyphenated UUID.
- `node create --format text|json|cbor` renders the creation report. The new
library module GitRoam.Output owns structured rendering, and the new output-tests
suite covers the text bytes and arbitrary filesystem path bytes in JSON (UTF-8
text plus a lossless Base64 representation) and CBOR (byte strings).
- Protection no longer binds a store-absolute executable path. The configured
command is `git-roam --reference-transaction`, resolved through PATH when the
Hook runs; `enable` migrates a recognized legacy absolute-path command and
refuses divergent configuration. An unreachable executable still fails the ref
update, so protection fails closed.
- Deployment exclusivity moved from the whole root to the new targets.
`checkOuterTargets` uses the outer repository index instead of `check-ignore`: a
shared root may hold unrelated tracked content, may be the outer worktree root
itself or sit inside an existing linked worktree, while occupied targets, indexed
targets and tracked file/gitlink ancestors are refused. The now-retired Discard
workflow reused the same check for its recreated worktrees, and outer ignore
configuration is still never edited.
- The discard recreation fixture stopped using partial `head`; an empty removal
plan returns an explicit failure instead of raising.
- CHANGELOG.org marks the matching Changed and Added items as checked; the entry
was later promoted to `NEXT v0.1.0` and then `DONE v0.1.0`.

Harness lesson: a test that runs the CLI with every `GIT_*` variable removed and
`GIT_CONFIG_GLOBAL=/dev/null` must also configure local `user.name`/`user.email`.
`node create` validates `git var GIT_AUTHOR_IDENT`/`GIT_COMMITTER_IDENT` before
writing objects, so such a test otherwise fails with exit 1 in a way that mimics
a product defect. This happened once in the new extreme-identity case.

Verification. That creation case first failed only through the missing identity;
after the fixture fix the same source content built with 14 suites and 288 cases
passing, no compiler warnings and a checkPhase of about 2 minutes. A later
`nix flake check` on the dirty tree built only treefmt-check, because the product
check derivation was already valid in the store; the logged results come from
that earlier build of identical content, not from a new post-commit test run.
The committed tree matches that content, including the separately committed
test-fixture fix, so this is content equivalence rather than post-commit testing.
README and CHANGELOG text are not executed by the build. Scope vocabulary also
widened: the user committed the identity change as
`feat(node-create): allow explicit Nil and Max UUID identities`, the first
feature-level scope; earlier production commits use `feat(git-roam):`.

## v0.2.0 protocol phase one

The user committed `docs: outline v0.2.0 protocol redesign` (README direction
plus the `TODO v0.2.0` CHANGELOG checklist) and then
`feat(protocol): introduce isolated v0.2.0 history model`. Phase one implements
the pure protocol only, in the temporary `GitRoam.Protocol.V2.*` namespace.

- `Protocol.V2.History` validates Root (no parents), Content (exactly one
  same-Node parent) and Checkpoint (first parent plus at least one context
  parent). A Checkpoint must keep its first parent's tree and its tree must not
  overlap a context commit's tree (enforced as a different Node identity,
  because each validated tree has exactly one top-level UUID directory).
  Repeated parent OIDs are refused, and one Node UUID keeps one Root across the
  validated graph.
- A commit tree has exactly one top-level canonical-UUID directory;
  `<uuid>/.roam` must be a regular or executable file whose content may change.
  A Root's UUID directory contains only that marker.
- Validation reads only the supplied local tips and their Git ancestors,
  memoizes immutable objects per invocation, and rejects mixed object formats,
  cycles, unavailable objects and wrong-type evidence. No remote query or
  unreachable-object scan is performed, and context commits need not remain
  reachable from their own Node's current branch.
- Queries are `firstParentHistory`, `contextParents` and `reachableHistory`
  (the last follows all parents).
- `Protocol.V2.Repository` exposes `ManagedState` as validated history plus
  managed refs, with no retained-Checkpoint set or cross-Node dependency
  closure. `validateManagedState` checks tip identity and missing tips;
  `validateOrdinaryTransition` lets a branch be rewritten but not removed and
  not silently assigned a different Root.
- `cabal/git-roam.cabal` registers both modules and the separate
  `protocol-v2-tests` suite. `cabal/test/ProtocolV2.hs` has 26 cases across
  SHA-1/SHA-256: Root/Content/editable markers, multiple context versions from
  one external Node, same-Node overlap rejection, duplicate parents, identity
  and Root conflicts, missing/cyclic evidence, local-ref retention limits and
  ordinary transition protection.

Only the Checkpoint-to-context tree disjointness is a protocol requirement;
pairwise disjointness among context commits is a recommended caller convention,
so several historical versions of the same external Node may all be contexts of
one Checkpoint.

The user reported that the phase-one patch applied cleanly and that its checks
passed. Both project main and origin/main point at that commit, so the commit and
push are observed; the check result is the user's report. No independent
post-commit run by the agent is recorded, and the suite was not re-executed here.

Phase one did not change product behavior. The remaining production commands
(`check`, `status`, `checkpoint`, `deploy`, `undeploy`, `node create`,
`node delete`) and the reference-transaction Hook still use v0.1.0. Do not
describe v0.2.0 as available.

## Discard retirement (phase-two preparation)

The commit `refactor(discard): retire formal-history discard workflow` removes
the specialized v0.1.0 successor-closure operation.

- Removed: the public `git roam discard` command with its argument parser,
  help topic, preview renderer, interactive confirmation and execution dispatch
  from `GitRoam.Cli`; `GitRoam.Protocol.Discard`;
  `GitRoam.Application.Discard`; the Discard-only worktree helpers
  `planDiscardRemoval`, `restoreRemovedWorktree` and
  `checkRemovedWorktreePaths`; the `discard-tests` suite and
  `cabal/test/Discard.hs`; and their Cabal registrations.
- Tests: `Unit.hs` now rejects `discard` and `help discard` as invalid arguments
  and asserts that help does not advertise the command. `Deletion.hs` no longer
  derives a mismatched plan token from a Discard preview. `Worktree.hs` drops
  the Discard-specific recreation cases. `EndToEnd.hs` now removes the
  referencing Node before the referenced Node, still under the v0.1.0 rule that
  an incoming dependency blocks deletion; this is not v0.2.0 context behavior.
- Documentation: `README.org` records that the command is retired on the
  development branch and that the remaining commands still use v0.1.0. The
  tagged v0.1.0 tree, `CHANGELOGS/v0.1.0.org` and the v0.1.0 history keep their
  original Discard documentation.
- Rationale: v0.1.0 needed retained formal Checkpoints and complete dependency
  closure, so withdrawing a selected successor closure was a required
  operation. v0.2.0 Checkpoints record caller-selected context with no inherited
  mapping or cross-Node branch-maintained closure, so the specialized command
  has no required role. Its removal is architectural simplification, not a new
  history-rewriting API; future read-only queries of reachability, first-parent
  history or context remain possible.

Operational state after this commit: `check`, `status`, `checkpoint`, `deploy`,
`undeploy`, `node create`, `node delete` and the reference-transaction Hook are
unchanged and still use v0.1.0 validation, so ordinary history rewriting is not
yet unrestricted. Discard retirement alone does not complete v0.2.0.

Verification of the committed tree is available from the local Nix store rather
than from a new agent run. The store source whose files match the committed tree
exactly (zero differences across all tracked files) has a `git-roam` derivation
with an existing output whose log reports 14 of 14 suites passing, 274 cases, no
compiler warnings and no `discard-tests`; `protocol-v2-tests` contributes 26
cases. The matching `treefmt-check` derivation also exists and its log reports 53
files traversed and 51 formatted with zero changes. An earlier build of the
pre-fix source failed at `Cli.hs` because `Set.toList` was out of scope after
`Data.Set` had been removed; the committed source restores that import. These are
local x86_64-linux results recorded from store logs; other platforms and the
minimum Git version remain unverified.

## v0.2.0 read-only inspection and build policy

The commit `feat(inspection): add isolated v0.2.0 native history validation`
adds `GitRoam.Application.V2.Inspect` and the separate `inspection-v2-tests`
suite, and turns warnings into build errors for every Cabal component.

- `V2.Inspect.inspectState` reads the local managed refs (or one requested Node),
  validates them with `Protocol.V2.History`/`Repository`, refuses shallow
  repositories, checks stored object connectivity through the raw object reader,
  and reports per-Node tip, commit kind, latest Checkpoint, direct context and
  the Checkpoint count in its first-parent history, plus Git-registered
  worktrees. External context never expands the managed ref selection, unlike
  the v0.1.0 dependency closure.
- `V2.Inspect.validateCandidate` validates a candidate ref map, stored
  connectivity and the resulting `ManagedState` without writing.
- Errors are explicit: repository discovery, Git transport, invalid output,
  symbolic Node branches, unmanaged Node, shallow repository, history failure,
  missing reachable objects, changing refs and invalid candidate state.
- `cabal/test/InspectionV2.hs` covers four scenarios plus a
  files/reftable x SHA-1/SHA-256 context matrix (8 cases): identity mismatch,
  conflicting Roots, overlap/tree-change refusal, Node-scoped inspection and
  contextual inspection.
- `cabal/test/ProtocolV2.hs` ignores one unused value with a wildcard so the
  `-Werror` policy holds.
- Every component (library, executable, 15 test suites) has
  `ghc-options: ... -Werror`. Any `-Wall` warning is now a build error; keep the
  tree warning-free.
- Verification from the local store: the whole-tree source matching the
  committed tree exactly (zero differences, no missing files) and the matching
  cabal subtree (zero differences, no extra files) correspond to a `git-roam`
  derivation with an existing output. Its log reports 15 of 15 suites, 282
  cases, zero compiler warnings and zero errors, including `inspection-v2-tests`
  (8 cases); `discard-tests` is absent. The matching `treefmt-check` derivation
  exists and reports 55 files traversed and 53 formatted with zero changes.
  These are local x86_64-linux results read from store logs, not a new agent
  run; other platforms and the minimum Git version remain unverified.

Production behavior is unchanged: `check`, `status`, `checkpoint`, `deploy`,
`undeploy`, `node create`, `node delete` and the reference-transaction Hook still
use `Application.Inspect` and the v0.1.0 protocol, and `V2.Inspect` is imported
only by its test suite. Do not describe v0.2.0 as available.

## v0.2.0 isolated Checkpoint, protection and deletion

Three further isolated commits complete the V2 preparation; production routes
remain on v0.1.0.

- `feat(checkpoint)` adds `GitRoam.Application.V2.Checkpoint.checkpoint`. It
  uses the Node's current tip as the first parent and the caller-selected
  commits as extra parents, keeping `tree(K) = tree(p)`; it never creates a
  synthetic Content commit or an inherited dependency map. Before construction
  it validates each context's own history and Git objects, refuses duplicate
  OIDs, self-history and invalid input, and preserves other named Hooks and
  failure diagnostics. It reuses the protected session, candidate validation
  and conditional ref updates, and checks that other managed refs did not
  change.
- `feat(protection)` adds `Application.V2.Protection.evaluateTransaction`. It
  accepts ordinary Content commits, amends and same-Root history rewrites
  without retained-Checkpoint or cross-Node closure rules, and rejects
  uncontrolled managed-branch creation/deletion, Root changes, duplicate
  updates to one Node, malformed updates and invalid history. Direct Content
  and amend use a single-Node check; Checkpoint updates, general rewrites and
  multi-ref transactions validate the complete managed state, so the fast path
  does not mask a cross-branch Root conflict. It checks actual managed refs
  rather than OIDs supplied by the Hook input.
- `feat(deletion)` adds `Application.V2.Delete.previewDelete` and
  `executeDelete`. A context edge no longer blocks deleting the referenced Node
  branch. The preview reports exclusive commits that are no longer reachable
  from the remaining managed tips and does not claim Git object deletion.
  Worktree checks, the confirmation token, operation lock, conditional refs,
  post-state validation and scoped local branch-configuration cleanup are
  retained.
- `CheckpointV2.hs`, `ProtectionV2.hs` and `DeletionV2.hs` each add 8 cases.
  They cover external context from unretained Content, invalid requests, dirty
  worktree preservation, other named Hooks, Root conflicts, locking,
  checked-out worktrees, stale plans and configuration cleanup.
- `CHANGELOG.org` notes that the V2 implementations exist only in temporary
  modules and checks only the retired-Discard item; the other v0.2.0 goals
  remain open.

Verification: the local store contains a whole-tree source and a cabal-subtree
source that match HEAD exactly (zero differences, no missing or extra files).
The corresponding `git-roam` derivation output exists and its log reports 18 of
18 suites, 306 cases, zero compiler warnings and zero errors; the matching
`treefmt-check` reports 61 files traversed and 59 formatted with zero changes.
The user reported each stage's tests passing; no independent agent rerun is
recorded. Only x86_64-linux is covered; other platforms and the minimum Git
version remain unverified.

## v0.2.0 cutover strategy and plan

The development handoff fixes the remaining strategy.

- Do not add more parallel `Application.V2.*` modules; `Create.V2`,
  `Deploy.V2` and `Worktree.V2` are explicitly rejected. Use the V2 modules as
  the prototype, refactor the formal modules against them, and reuse the
  existing Git object reading, worktree safety planning, conditional ref
  updates, operation lock, compensation and diagnostics instead of copying
  them.
- Port and de-duplicate the existing V2 application modules selectively; do
  not overwrite the v0.1.0 implementations wholesale.

Stages are task boundaries, not a fixed commit count:

- A: unify the formal protocol, repository-state and inspection interfaces and
  enumerate every remaining old dependency-closure coupling. A rename of
  `Protocol.V2.*` to `Protocol.*` that leaves old callers uncompilable is not a
  valid intermediate state; merge that rename with B when necessary.
- B: wire every public command and the installed `reference-transaction` Hook
  to the single v0.2.0 protocol, remove the temporary `V2` namespace and old
  protocol-only modules, tests and aliases, and keep no dual production path.
  The public Checkpoint CLI spelling and arguments, `check`/`status` wording
  and the safety boundary of the single-Node fast path remain open interface
  decisions.
- C: migrate and extend end-to-end tests through the real CLI and installed
  Hook (context anchoring, Root conflicts, non-cascading deletion, multi-ref
  races, object-format matrices, dirty/locked/moved worktrees, missing or
  shallow evidence, other Hooks), then update README, help and CHANGELOG and run
  the full build and check before release. Tag creation and a release page are
  separate events.

Non-blockers for v0.2.0: deployment acceleration, alternative deployment
layouts or `.roam` deployment metadata (v0.3.0 or later), cross-Node batch
content tooling, Org-link auto-synchronization, v0.1.0 migration or
compatibility guarantees, and any extra rule that a referenced Checkpoint can
never expire.

## Completed reader verification and prior authorization

The user requested a new isolated flake-managed performance retest of the
committed production reader using the archived 1,000/10,000-Node fixtures.
The new experiment is tmp/committed-reader-performance/, with an exact
50-file source copy reconstructed from the committed optimization, the original
byte-verified fixture recipe and lock, and archived expected stream/result
hashes. Build, isolated flake check and all six measurements passed. Production
medians: 1,000 Nodes 0.190307s / 30.11 MiB max RSS; 10,000 Nodes 2.455161s /
243.54 MiB. Every run uses one raw child / 11 total Git launches and matches the
archived stream/result digests. Three runs per scale were serial, one capability,
1 GiB managed heap, single Nix job/core; no timeout, failed run or retry. No
product edits, original archive edits or old run replacement. Follow the
committed-retest section in raw-reader-implementation.md for measurements,
controls and limits. That retest is complete and is not the current next action.

### Completed production implementation

The user now explicitly requested production integration of the persistent raw
reader, preserving all protocol semantics and requiring lifecycle/error tests
plus performance revalidation. Follow
[raw-reader-implementation.md](raw-reader-implementation.md) for current code,
test design, completed verification and recovery boundaries. Session/adapter/shared-validator code,
tests and documentation are written; the corrected 50-file build passed all
274 cases / 13 suites and flake/format checks. Actual production performance
revalidation completed all 24 measurements in a new isolated experiment, with
matching result digests and original fixture hashes. At 10,000 Nodes the formal
implementation medians are 109.6696s one-shot versus 2.7429s production (~40x),
60,011 versus 11 Git launches, and 345.7 versus 243.6 MiB maximum RSS. Every
production run uses exactly one raw batch process. Longer dependency-history
measurements also passed. The Changed checkbox is checked; final formatting,
build and flake check passed, and all 50 current files match the final verified
snapshot. The user committed the production optimization as
`perf(git-roam): reuse a persistent raw object reader per validation`.
Read-only comparison confirms all 50 committed files match the final verified
snapshot, with no additional tracked files; the project worktree is clean.
The committed implementation is complete. No duplicate build or performance
rerun is needed solely for the commit acknowledgment. Do not start unrelated
optimizations or a release. Nix command authorization
applies to the completed task and does not broaden future task scope.

The preceding independent experiment (before production authorization) was an
isolated flake-managed raw-object performance measurement for potential
10,000-Node use. Follow
[object-reader-performance.md](object-reader-performance.md) for the confirmed
per-object process behavior, experiment design, actual command authorizations,
results and limits. The user authorized commands 1–4 and requested bounded parallelism.
Experiment files/source are under tmp/object-read-performance/. Corrected locking,
single-job/core build and all pilot measurements passed. At 1,000 Nodes the
baseline median is 12.2585s / 6,011 Git processes versus 0.1846s / 11 for the
experimental persistent adapter; digests agree. The original 10,000-Node stage ran
serially with one GHC capability and a 512 MiB managed heap limit. Its first
persistent run passed in 2.5497s / 11 processes. The baseline then exhausted that
configured heap after 120.89s (exit 251) and the stage stopped without retry or
OS OOM. No 10,000-Node paired median follows from that run. The user asked about
raising the cap and then explicitly authorized the new 1 GiB command on demand.
That stage completed all six runs with unchanged 180s child deadlines and matching
result digests. At 10,000 Nodes the medians are 121.2960s / 60,011 Git launches
for baseline and 1.7260s / 11 for the persistent prototype (~70.3x). Median max
RSS is ~346.8 MiB / ~185.2 MiB. Pilot and both scale budgets are preserved; no
further measurements or cap changes are needed. The completed report and 14
byte-verified small evidence files are preserved in
archive/2026-11-01T18-39-43Z--raw-object-reader-performance/. That experiment-only
task left project source clean and did not authorize a
production reader change, DAG change or permanent cache. The current explicit
production implementation task above supersedes that completed task boundary;
keep the prototype and production measurements distinct.

Node 11's discard execution, node 12's confirmed non-cascading deletion and node
13's end-to-end lifecycle are complete. The post-node-13 additions are recorded
above: explicit UUIDs including Nil/Max, lossless text/JSON/CBOR creation output,
PATH-resolved Hook configuration, target-scoped shared-root deployment, and the
persistent raw-object reader. The verified 288-case build is the last recorded
complete matrix for the post-node-13 creation updates; later scoped reader
checks are documented separately. Do not treat either as a fresh release check.
The accepted production evidence is principally x86_64-linux with pinned Git
2.56.0; minimum Git 2.54 and other declared systems are not fully verified.

## Release freeze and subsequent work

The user has explicitly chosen to release v0.1.0 as the complete first
knowledge-dependency-DAG implementation despite a planned semantic change. It
has no known actual consumers or established workflow. Preserve the old protocol
and its documentation in v0.1.0; do not insert the proposed v0.2.0 semantics
into its README or release notes. The freeze, the `NEXT -> DONE` transition with
its UTC `CLOSED` time and the annotated `v0.1.0` tag are all recorded in project
main; the human performed that transition and the tag. Publication is not
established; the README now states that v0.1.0 is finalized and tagged and keeps
its command documentation on v0.1.0.

The deferred deployment-directory naming and full-set deployment acceleration
are non-blockers. Existing deployment already supports the complete Node set,
but does not implement the proposed bulk checkout acceleration. A separate
cross-Node Content-edit workflow may reduce manual repeated `git commit` work;
it is an optional later capability, not a v0.1.0 prerequisite. Do not start
these implementations as part of the protocol cutover.

Next action: execute stages A/B/C of the v0.2.0 cutover described above, first
listing every production call site and choosing one atomic buildable cutover
boundary. Discard retirement is complete and no longer pending. Include the
mandatory removal of the temporary `V2` namespace, without a default promise to
migrate v0.1.0 repositories.
Follow [context-checkpoint-direction.md](context-checkpoint-direction.md) for
accepted semantic direction and unresolved engineering details. Do not modify
v0.1.0 history or retroactively recast its formal dependencies as contexts.

This checkpoint records planning knowledge; it does not authorize mutating
project refs, staging, builds, release finalization or further GAW checkpoints.
Respect project AGENTS.md and the GAW public workflow. Preserve archives and
prior snapshots; approvals for completed tests and experiments do not extend to
new commands.
