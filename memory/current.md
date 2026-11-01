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
worktree was clean at transition. Node 2 is now implemented and verified, awaiting
user review/staging/commit: pure permanent history protocol and projection, with
corresponding tests and README. Its final build passed 36 protocol cases and the
existing 21 cases, with no compiler warnings, and flake check passed. No new CLI
command is advertised; do not start node 3 before the user's node-2 commit.

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

README.org retains the user's title/author and now documents the implementation's actual
help/version interface, build/check commands, native Git selection and tests.
The committed CHANGELOG.org roadmap
preserves its canonical Org header and TODO 0.1.0, and adds unchecked planned
user-facing features under Added. It explicitly separates optional naming and
acceleration candidates from the current batch, and makes no no-op/scaffolding
claims. No product feature checkbox is marked complete.

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
tmp/git-roam-milestone2-source/, separate from node 1. Project index is empty;
diff --check passes. Results describe uncommitted node-2 source and do not
justify a new project parent for this handoff checkpoint.

## Next action and authorization

Present node 2 for user review and staging. After staging, review the actual index
and prepare the commit message; wait for the user's commit before node 3. Then
confirm exact committed provenance. Do not stage or commit project files.
No additional verification repetition is needed absent changes or new concerns.
Preserve both independent archives and earlier source snapshots. Node 3 implements
repository object loading, shared managed-state validation, check and status.

The request to implement covers the plan's project edits. Respect AGENTS.md for
build/test/format/network command authorization and project Git boundaries.
Ordinary GAW memory maintenance is preauthorized through its public loop; lifecycle
changes or native project commits are not implied. Preserve the existing archive,
user edits and unrelated temporary work. No new command approval is inherited
from the completed reproduction.
