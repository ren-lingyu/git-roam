# Git Roam current state

## Objective and actual progress

The user accepted the revised v0.1.0 plan and requested implementation on
2026-11-01. Execute serially, one independently reviewable/buildable/testable
project commit at a time, with user-performed project staging and commits.

Current work is the mandatory GAW design consolidation/checkpoint, followed by
project commit 0 (CHANGELOG feature roadmap only). No application implementation,
new native-Git experiment, build, formatter, or test run has occurred in this
phase. Do not skip ahead to milestone 1 before the user commits node 0.

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
text rather than restoring old agent prose. CHANGELOG.org currently has its
canonical Org header, TODO 0.1.0 and empty Added. Commit 0 will add explicitly
planned real user-facing features, not no-op/scaffolding claims.

## Verification and provenance limits

Earlier skeleton build/flake checks passed on x86_64-linux with GHC 9.10.3, before
or around the user's README correction; those are not fresh checks of every
later tree. Other declared platforms were not thereby validated. The formal
design consolidation is supported by user decisions and current small-file
inspection, not by a new protocol implementation or native-Git experiment.

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

Finish reviewing/staging/checkpointing the coherent declared GAW workspace through
public interfaces. Then change only root CHANGELOG.org for project commit 0;
verify its diff and obtain any required formatter/check command authorization.
Present the reviewable result and suggested commit intent, await the user's
project staging/commit, and read-only confirm it before new experiments.

The request to implement covers the plan's project edits. Respect AGENTS.md for
build/test/format/network command authorization and project Git boundaries.
Ordinary GAW memory maintenance is preauthorized through its public loop; lifecycle
changes or native project commits are not implied. Preserve the existing archive,
user edits and unrelated temporary work. No new command approval is inherited
from the completed reproduction.
