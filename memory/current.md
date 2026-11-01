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
Project node 1 is now implemented and verified in the worktree: CLI help/version, library, binary
Git transport, opaque SHA-1/SHA-256 OIDs, repository discovery, two test suites,
Nix Git selection and README. Formatting, build, all 12 unit and nine integration
cases, and flake check passed on x86_64-linux. Changes are not staged or committed.
Wait for the user's project commit before node 2; no Node lifecycle command is
publicly advertised by this foundation.

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

The committed project remains the empty executable plus the roadmap. The node-1
worktree implementation adds GitRoam.Cli/Git/ObjectId/Repository and private BuildInfo, using
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

GHC 9.10.3 built the implementation. Both test suites passed (12 unit and nine
integration cases). The fresh treefmt check reported zero changes; other declared
platforms were omitted. A subsequent user review removed the initial Nix preCheck
workaround and GIT_ROAM_TEST_EXECUTABLE override. Tests now use only the internal
Cabal build-tool-depends declaration and findExecutable/makeAbsolute, following
the inspected GAW test organization. No test binary path is hard-coded in Nix.

The lookup failure was reproduced with the GHC-bundled Cabal 3.12.1.0: its
component graph correctly includes and builds exe:git-roam before the adapter
tests, but Setup test does not expose it on the test process PATH. Selecting
haskellPackages.Cabal_3_14_2_0 in setupHaskellDepends made the same tests pass
without any executable-path injection. Nix now selects the Setup driver version;
the Cabal file remains the sole declaration of test suites and the internal tool
dependency. README explains the observed version boundary. This comparison does
not establish the earliest fixed Cabal release or explain GAW's runtime toolchain;
only its source organization was inspected. No library/compiler/lockfile upgrade
or custom Setup script was needed.

The clean snapshot contains 20 explicitly enumerated files, including eight new
untracked Haskell files, and excludes .git/.agents/unrelated ignored content.
Final read-only comparison confirmed every project and copied file matches the
tested manifest. Manifest SHA-256:
37b63970af4a357e6f71167d763ba9002df805441ed1cf039fee8df76c40ed0f.
Git diff --check passes and the project index is empty. CHANGELOG and lock inputs
are unchanged. The successful package derivation is
/nix/store/zpzz1iw9f986lymazqyy09q9sglsi37y-git-roam-0.1.0.drv.
These results describe an uncommitted worktree snapshot, not project HEAD 8f1fed2;
they do not justify a new project parent for this GAW checkpoint.

## Next action and authorization

The test-discovery review is resolved and the final no-injection version passed
formatting, build and flake check under the existing task command authorization.
Present node 1 for user staging. Once staged, review the actual index
and prepare its commit message, then wait for the user's commit. Confirm that
commit and its relationship to the tested source before advancing to node 2.
Do not stage or commit project files automatically. Preserve both independent
archive snapshots. No additional build/check repetition is needed absent changes.

The request to implement covers the plan's project edits. Respect AGENTS.md for
build/test/format/network command authorization and project Git boundaries.
Ordinary GAW memory maintenance is preauthorized through its public loop; lifecycle
changes or native project commits are not implied. Preserve the existing archive,
user edits and unrelated temporary work. No new command approval is inherited
from the completed reproduction.
