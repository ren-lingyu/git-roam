# Git Roam current state

## Objective and actual progress

The user accepted the revised v0.1.0 plan and requested implementation on
2026-11-01. Execute serially, one independently reviewable/buildable/testable
project commit at a time, with user-performed project staging and commits.

The mandatory GAW design consolidation/checkpoint is complete. Project commit 0
is drafted: only root CHANGELOG.org is modified in the project, without staging
or committing. Its diff passes git diff --check. The user authorized the three
listed Nix commands in sequence: formatting and package build passed, but the
path:. flake check failed in treefmt when its Git transaction invoked the GAW
Hook and git-gaw was unavailable. A Git-source check retry needs fresh command
authorization, which has been requested; it has not run yet.
No application implementation or new native-Git experiment has occurred.
Do not skip ahead to experiments or milestone 1 before the user commits node 0.

## Navigation and authority

- [design.md](design.md): effective standard knowledge model, Content/Checkpoint
  encoding/projection, managed closure, lifecycle, deployment, discard and delete.
- [implementation.md](implementation.md): accepted plan, experiment gate, serial
  project commits, execution defaults, validation and authorization boundaries.
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

The project remains the empty Haskell executable: cabal/app/Main.hs is main =
pure (); cabal/git-roam.cabal is version 0.1.0 with base and no library/tests.
The Cabal/Nix layout and locked inputs already exist. Package checks are enabled;
declared platforms are x86_64-linux, aarch64-linux and aarch64-darwin.
No experimental or patched Git is wired into the application.

README.org still contains only the user's title/author. The new task authorizes
README growth alongside verified implementation; preserve the user's existing
text rather than restoring old agent prose. The uncommitted CHANGELOG.org draft
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

The authorized timeout 120s nix flake check --no-write-lock-file -L path:.
failed with exit 1 in checks.x86_64-linux.treefmt. The relevant builder output was
git-gaw --reference-transaction: command not found, followed by Git aborting its
preparing transaction. Read-only git config confirmed the matching named Hook
command in local .git/config. Explicit path: source including Git metadata is
the suspected cause; the corrected Git-source check is not yet verified.
The proposed retry is timeout 120s nix flake check --no-write-lock-file -L .,
which includes tracked worktree edits without copying .git as source. Do not
disable real protection or edit flake/config to conceal this failure. This tracked
CHANGELOG needs no staging for that source selection. Native Git experiments and
product tests have not started.

The completed independent reproduction remains separately archived. Its source-
pinned 2.54 and nixpkgs-patched 2.56 no-checkout results do not establish product
protocol, Hook, real checkout or minimum-Git support. The new plan requires a
separate flake-managed standard-Git experiment after project commit 0.

No additional project parent is selected for this design/planning checkpoint:
these semantic decisions and the execution plan were not derived from testing
a new committed application implementation. Existing first-parent memory retains
the original bootstrap/changelog provenance. Do not guess a project parent from
current HEAD or a future commit.

## Next action and authorization

Obtain the pending authorization for the one corrected Git-source flake check;
do not repeat the original three commands or assume repeated-run permission.
Review its result while keeping project commit 0 limited to CHANGELOG.org.
Present the verified result and the accepted commit intent, await the user's
project staging/commit, and read-only confirm it before new experiments. Current
memory's progress update follows the completed design checkpoint; checkpoint
again only when the resulting verification/handoff state has recovery value.

The request to implement covers the plan's project edits. Respect AGENTS.md for
build/test/format/network command authorization and project Git boundaries.
Ordinary GAW memory maintenance is preauthorized through its public loop; lifecycle
changes or native project commits are not implied. Preserve the existing archive,
user edits and unrelated temporary work. No new command approval is inherited
from the completed reproduction.
