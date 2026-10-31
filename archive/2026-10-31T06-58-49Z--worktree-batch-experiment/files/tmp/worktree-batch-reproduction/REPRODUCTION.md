# Worktree batch reproduction — 2026-10-31

Both phases passed on Linux x86_64 with Nix 2.34.9. All files are isolated under
this ignored experiment directory; the Git Roam main flake is unchanged.

## Inputs and phase separation

The supplied ZIP has SHA-256
`d63547595d2de0bed3b4a3745c173a470a1deaea999a7d7e4a80f9ad44b19485`.

- Both phases use nixpkgs commit `885ba4d038f10c3d17d7a92e8c3cc185b99c9158`,
  locked with `sha256-e/yiZ31gXRROBDcnOtT3YwDQ73NVG9Cepccbt86LIn8=`.
- Phase 1 reproduces the archive's Git 2.54.0 source commit
  `94f057755b7941b321fd11fec1b2e3ca5313a4e0`, locked with
  `sha256-bA144ECODQIly1q0xilmTMYrHmvBrMF5DfBsEMd4YyY=`. All three experimental
  patch files are unchanged. This complete configuration and measurements are
  preserved in `phase1-fixed-source/`.
- Phase 2 is the active root flake. It has only the locked nixpkgs input and
  appends patches to `pkgs.gitMinimal` (Git 2.56.0). It does not override `src`,
  `version`, build flags, or nixpkgs' own patches. It does not independently fetch
  a Git source tree. The package recipe in locked nixpkgs owns its source/hash.

The API port between phases is limited to passing `the_repository` to
`get_worktrees` and `check_branch_ref` in the patch files. An explicit content
comparison verified that no other patch text changed. Selective original and
patched source copies in `porting/` are diagnostic artifacts, not flake inputs.

## Build corrections and evidence

The first phase initially failed linking HTTP helpers: the source checkout had
no generated configure script, and direct Makefile compilation could not find
curl-config. `NO_CURL=1` was added to all three phase-1 variants for this local
worktree experiment. The successful build log records the same source and
unchanged cumulative patches. Phase 2 uses nixpkgs' release-source configuration
and needs no equivalent override.

The unmodified 2.54 patches did not initially apply to nixpkgs' Git 2.56.0 due
to API changes; the above repository-argument port fixed application/compilation.
Both initial failures and corrected successes remain in logs.

- Phase 1's final patched, baseline, and list-reuse builds each reported
  `Files=1026, Tests=28587`, `Result: PASS` in their available upstream suites.
- Phase 2's patched and list-reuse builds each reported
  `Files=1043, Tests=29449`, `Result: PASS`. The baseline is nixpkgs' unchanged
  `gitMinimal`. These summaries include skips for unavailable/disabled features;
  they do not mean every possible upstream feature was tested.
- The original smoke passed in both phases for `files` and `reftable`: three
  successful registrations, then an injected failure with rollback.
- Each phase passed 18 additional cases (nine per ref backend): invalid final
  branch, duplicate path, duplicate branch, nested destinations, existing user
  directory, failure during registration, failure after registration, occupied
  branch, and forbidden `--force`. Assertions check preservation of existing user
  data, unchanged worktree listings/admin entries after rejected/failed batches,
  destination cleanup, and absence of the batch lock afterward.
- Successful benchmarks additionally validate worktree counts, each gitfile,
  administrative entry counts, and removal of initialization locks.

## Fresh measurements

Seconds below are medians of three samples per case. Each sample uses a fresh
empty repository and pre-existing branches. The clock covers registration only,
not setup, branch creation, post-run validation, or cleanup. There is no file
checkout. Shared executable/source caches are warm; this is not a cold-cache,
fsync/power-loss, large-content, or end-to-end Git Roam deployment benchmark.
Variants run in a fixed order. Hardware/filesystem/load effects are not isolated,
so do not interpret these as portable timings or compare exact speedups against
historic numbers from the ZIP.

| Git / source | Backend | Sequential 700 | List reuse 700 | Batch 700 | Batch 1500 | Batch 5000 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 2.54.0 source-pinned | files | 11.607943 | 9.456971 | 0.092464 | 0.186838 | 0.630921 |
| 2.54.0 source-pinned | reftable | 16.189015 | 14.339478 | 0.125408 | 0.247258 | 0.802834 |
| 2.56.0 nixpkgs source | files | 11.786607 | 9.306987 | 0.095162 | 0.181236 | 0.577271 |
| 2.56.0 nixpkgs source | reftable | 16.182027 | 13.902755 | 0.128674 | 0.248414 | 0.773390 |

All 60 timed samples passed validation. The measurements support substantial
registration savings from the final cumulative batch method in this workload.
List reuse alone offers a smaller improvement. The no-src-override phase achieves
the same behavior and broadly similar timings while keeping source ownership in
nixpkgs; it is the preferred packaging direction requested by the user.

## Artifacts and commands

See `README.md` for commands. The active `flake.nix`/`flake.lock` reproduce phase 2;
`phase1-fixed-source/flake.nix`/`flake.lock` reproduce phase 1. Their `results.json`
files retain all raw samples, medians, binary store paths, reported Git versions,
and method details. `MANIFEST.json` fingerprints the inputs, reports, results,
and logs retained by this reproduction.

Phase-1 benchmark output:
`/nix/store/vwpv65j5ba4vv8bddmr4k69i5fgkllr3-git-roam-worktree-benchmark`.
Phase-2 benchmark output:
`/nix/store/cc8kdz3a7672rc8f77wdv0342dngjyqr-git-roam-worktree-benchmark`.
Local JSON copies do not depend on these store outputs surviving garbage
collection. Keep the complete directory and both lockfiles to retain this run.

Logs:
- `logs/lock.log`, `logs/build-01.log`, `logs/build-02.log`: original source lock,
  initial HTTP-link failure, and corrected patched build.
- `logs/check-01.log`, `logs/check-02-benchmark.log`, `logs/check-03-safety.log`:
  phase-1 smoke, performance variants/measurements, and safety checks.
- `logs/phase2-lock.log`, `logs/phase2-build-01.log`, `logs/phase2-build-02.log`:
  removal of the independent source input, original patch-context failure, and
  corrected Git 2.56.0 build.
- `logs/phase2-check-01.log`: phase-2 smoke, safety, list-reuse build, and timings.

Nix checks may be served from cache. A later successful `nix flake check` can
reuse these measurements; it is not evidence of a new timing run. The lockfiles
fix the environment and input sources, not wall-clock outputs. The benchmark
JSON is observational and is not intended to be bit-for-bit deterministic.

## Limits

This is still an experimental Git extension, not a Git Roam feature or standard
Git interface. Batch locking covers cooperating batch invocations only.
Preflight and best-effort rollback are not a strict filesystem transaction.
These runs do not establish SIGTERM/SIGKILL/power-loss recovery, concurrent normal
Git writers or user edits, cross-platform behavior, real-content checkout, or
10000-worktree scaling. Production integration and broader failure testing
remain separate work.
