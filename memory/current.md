# Git Roam current state

## Objective and actual progress

The user accepted the revised v0.1.0 plan and requested implementation on
2026-11-01. Execute serially, one independently reviewable/buildable/testable
project commit at a time, with user-performed project staging and commits.

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
was clean at transition. Node 9 is implemented and verified in the worktree,
awaiting user review/staging/commit, with all 172 cases passing.

## Navigation and authority

- [design.md](design.md): effective standard knowledge model, Content/Checkpoint
  encoding/projection, managed closure, lifecycle, deployment, discard and delete.
- [implementation.md](implementation.md): accepted plan, experiment gate, serial
  project commits, execution defaults, validation and authorization boundaries.
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
Node-4 protection lifecycle and Hook changes remain uncommitted; mutating Node
history/worktree commands are still later work.

README.org retains the user's title/author and now documents the implementation's actual
help/version and inspection interfaces, build/check commands, native Git selection and tests.
The committed CHANGELOG.org roadmap
preserves its canonical Org header and TODO 0.1.0, and adds unchecked planned
user-facing features under Added. It explicitly separates optional naming and
acceleration candidates from the current batch, and makes no no-op/scaffolding
claims. At the node-2 committed baseline no product checkbox was complete; the
node-3 worktree marks only inspection/status complete, as detailed below.

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
introduced. Removal preflights all targets, protecting staged/unstaged/untracked/
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
Only the new Node is deployed; other undeployed Nodes are not implicitly deployed.
Internal plans carry an explicit operation target set: full deploy still targets
all Nodes, while creation targets only the new one. Review found the original
reuse of full-deploy planning incorrectly refused unrelated main/locked worktrees;
that restriction is corrected and covered by two additional regression groups.
Valid existing linked directories are still recognized for deployment-root reuse.

Cabal adds uuid for UUIDv4 generation, selected from locked nixpkgs (1.3.16.1 in
this build). The library accepts an injected identity generator for deterministic
collision tests, but the CLI exposes no user-selected UUID. New identities must
have v4/variant bits; historical identity parsing is unchanged. Current managed
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

## Next action and authorization

Present node 9 for user review/staging. Prepare the commit message from the actual
staged diff when requested, then wait for the user's project commit. Confirm its
source against the 42-file snapshot before node 10 (read-only explicit-discard
impact preview). Do not begin node 10, stage/commit project files or install project
protection. No further tests absent source changes or new concerns. Preserve
archives and earlier snapshots.

The request to implement covers the plan's project edits. Respect AGENTS.md for
build/test/format/network command authorization and project Git boundaries.
Ordinary GAW memory maintenance is preauthorized through its public loop; lifecycle
changes or native project commits are not implied. Preserve the existing archive,
user edits and unrelated temporary work. No new command approval is inherited
from the completed reproduction.
