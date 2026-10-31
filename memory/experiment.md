# Worktree batch reproduction

## Scope and source

The user supplied a design-history ZIP and requested read-only review, then
authorized reproducing its Git worktree batch experiment in isolation with Nix.
The main project remains an empty executable. Do not integrate experimental Git
into its flake or describe the experiment as an implemented Git Roam feature.

The archive is `tmp/git-roam-v0.1.0-design-and-experiment.zip` (SHA-256:
`d63547595d2de0bed3b4a3745c173a470a1deaea999a7d7e4a80f9ad44b19485`).
It contains a consolidated design history, not all original transcripts/logs,
plus three cumulative Git 2.54.0 patches, an isolated flake and smoke script.
The patches are one cumulative method: worktree-list reuse, experimental batch
registration, and whole-batch validation/cooperative locking/best-effort rollback.
It does not promise crash atomicity or exclusion of ordinary Git writers.

All reproduction artifacts are under `tmp/worktree-batch-reproduction/`.
The user prefers eventual integration by patching a nixpkgs Git derivation,
without an independent Git source input. They requested first reproducing the
original source-pinned experiment, then repeating without overriding src.

## Verified phase 1

The original Git commit `94f057755b7941b321fd11fec1b2e3ca5313a4e0` (2.54.0)
and nixpkgs commit `885ba4d038f10c3d17d7a92e8c3cc185b99c9158` are locked
with narHashes. The archive's three patches were applied unchanged.

A direct source override initially failed HTTP linking due to missing curl-config.
Setting NO_CURL=1 for all three phase-1 variants fixed this local-only experiment.
The patched build and baseline/list-reuse builds passed their available upstream
test suites (each reported 1026 files, 28587 tests; unsupported features skipped).
The original smoke passed for files and reftable. An added safety script passed
18 cases covering all-batch preflight errors, occupied branches, forbidden force,
in-progress and post-registration failures, metadata rollback, and user-file
preservation.

Benchmarks compare original sequential, list-reuse sequential, and final batch
at 700 worktrees, plus batch at 1500/5000, on both ref backends, three fresh-repo
samples each. Setup, validation, and cleanup are excluded; this measures
no-checkout registration, not cold-cache checkout or durability under crashes.
Phase-1 medians in seconds:
- files, 700: baseline 11.607943; reuse 9.456971; batch 0.092464.
- reftable, 700: baseline 16.189015; reuse 14.339478; batch 0.125408.
- files batch, 1500/5000: 0.186838 / 0.630921.
- reftable batch, 1500/5000: 0.247258 / 0.802834.

Phase-1 flake, lock, scripts, original patches, and raw results.json are preserved
in `phase1-fixed-source/` within the experiment. Logs remain in its parent logs/.
Its benchmark output is /nix/store/vwpv65j5ba4vv8bddmr4k69i5fgkllr3-git-roam-worktree-benchmark.

## Verified phase 2 and preferred packaging

The active experiment flake now has only the fixed nixpkgs input. It uses
pkgs.gitMinimal (Git 2.56.0), appends to old.patches, and overrides neither src
nor version nor build flags. First application of the original patches failed
due to Git API changes. Porting adds the_repository to get_worktrees and
check_branch_ref calls in the three patches. A direct content comparison confirmed
these are the only patch-text changes from phase 1.

The patched and list-reuse builds passed their available upstream suites
(each reported 1043 files, 29449 tests; unsupported features skipped).
The original smoke and all 18 safety cases passed on both ref backends.
The same benchmark matrix ran three samples per case, with all 30 validated.
Phase-2 medians in seconds:
- files, 700: baseline 11.786607; reuse 9.306987; batch 0.095162.
- reftable, 700: baseline 16.182027; reuse 13.902755; batch 0.128674.
- files batch, 1500/5000: 0.181236 / 0.577271.
- reftable batch, 1500/5000: 0.248414 / 0.773390.

The active flake's additive overrideAttrs approach satisfies the user's request
to keep source acquisition/version/build choices in nixpkgs. The stage-1
NO_CURL workaround is not present in this active flake. No main-project
integration was performed.

Phase-2 raw samples are in the experiment root's results.json; its store output
is /nix/store/cc8kdz3a7672rc8f77wdv0342dngjyqr-git-roam-worktree-benchmark.
REPRODUCTION.md compares both phases and documents corrections, exact locks,
test coverage, timing method, and limits. MANIFEST.json fingerprints retained
inputs/results/logs. Original ZIP and project worktree remained unchanged.
Nix may reuse benchmark outputs; a cached flake check is not a fresh timing run.
Timings are observational, not bit-for-bit deterministic artifacts.

The user authorized selective reading/copying of branch.c, branch.h, and
builtin/worktree.c from Nix's already downloaded Git 2.56.0 archive for porting;
copies are under porting/. No additional independent Git source fetch is needed.

## Execution and next action

For this task, the user authorized repeated executions from the experiment root:
- timeout 120s nix flake lock path:.
- timeout 600s nix build --no-link --no-write-lock-file -L path:.#patched-git
- timeout 600s nix flake check --no-write-lock-file -L path:.

These may download Nix dependencies and write lockfiles/logs in the experiment,
Nix store/cache, and sandbox scratch repositories. Nix daemon access needs host
escalation. Preserve logs and the phase-1 snapshot. The root smoke script uses
a dedicated experiment_root rather than repurposing HOME. No main-project
staging, commit, dependency changes, or test execution was authorized.

The requested two-phase reproduction is complete. Await the user's next task;
do not integrate into the application or claim a production-ready Git extension
without further work. Both locked environments, exact patch variants, logs, and
60 raw timed samples are retained in the ignored experiment directory.

Current evidence covers local no-checkout registration through 5000 worktrees,
preflight failures, and injected registration failures. It does not reproduce
SIGTERM/SIGKILL/power-loss or concurrent unpatched writers/user edits, does not
measure actual file checkout or 10000 worktrees, and is only x86_64-linux.
The full archive design has not been implemented in Git Roam.

No additional project parent is selected for this experiment checkpoint: work
used the supplied ZIP and isolated Nix derivations, not an application snapshot
modified or tested during this task. Existing bootstrap/changelog associations
remain in first-parent GAW ancestry. Input pins/hashes above identify external
experimental sources without importing their Git history.
