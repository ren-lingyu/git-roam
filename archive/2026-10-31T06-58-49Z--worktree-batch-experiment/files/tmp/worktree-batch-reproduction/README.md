# Isolated worktree batch reproduction

The active flake appends three experimental patches to `pkgs.gitMinimal` from
locked nixpkgs. It does not override `src`, `version`, or build flags and has no
independent Git source input. The pinned nixpkgs provides Git 2.56.0.

The first experiment, using the archive's Git 2.54.0 source pin and unchanged
patches, is preserved separately in `phase1-fixed-source/`. Its local-only build
needed `NO_CURL=1`. The active flake retains nixpkgs' original package patches;
its experiment patches adapt `get_worktrees` and `check_branch_ref` calls to the
Git 2.56.0 API by passing `the_repository`.

Run from this directory:

```sh
nix build --no-link --no-write-lock-file -L path:.#patched-git
nix flake check --no-write-lock-file -L path:.
```

To repeat the source-pinned first phase, run those commands from
`phase1-fixed-source/` instead. Both phases retain their own `flake.lock`.

The checks include the original smoke script, 18 additional safety cases, and a
performance comparison. Both `files` and `reftable` backends are covered.
The safety cases check whole-batch rejection, existing user files, occupied
branches, forbidden force, injected failure during/after registration, worktree
metadata rollback, and batch-lock cleanup.

The benchmark compares baseline sequential registration, one-patch list reuse,
and final three-patch batch registration at 700 worktrees, then batch registration
at 1500 and 5000. Each case runs three times in a fresh empty repository with
existing branches. Timing excludes repository/branch preparation, validation,
and cleanup. Validation checks worktree counts, gitfiles, administrative entries,
and absence of initialization locks.

`REPRODUCTION.md` records the observed results, artifact paths, and limitations.
Raw measurements are retained as JSON and build/check output under `logs/`.
Nix may reuse cached checks, including benchmark measurements; a later cache hit
is not a new timing run. Environment and method are pinned, not wall-clock times.

The batch operation is an experimental Git extension. Its lock coordinates only
cooperating batch writers. Preflight and best-effort rollback do not provide
crash atomicity or coordination with ordinary Git worktree writers. This
reproduction does not establish SIGKILL/power-loss, concurrent user edits,
cross-platform, real-file checkout, or 10000-worktree behavior.

This directory is independent of the Git Roam application's main flake. The
upstream archive remains unchanged in its parent directory.
