# v0.2.0 reader and shared-ancestry performance experiment

Production input is exactly main d8503afd02ae02ab38c604888c0c84e1e2a3cbdb,
restored as 51 small files by prepare.py. It reads Git blobs with the host's
mapped absolute Git executable; if restoring elsewhere, substitute an available
read-only Git executable for that preparation command. SOURCE.json records
original blob IDs and SHA-256 hashes. No project branch/index/source writes.

For a full-preview algorithm control, legacy-source/ differs only in the
Delete.collect remaining-tip expression: mapM singleton reachableHistory plus
Set.unions replaces reachableHistoryFrom. No protocol, reader, safety or other
application changes are made. This is a narrow current-code control, not a
benchmark of the complete pre-cutover release. Both source copies were verified
against SOURCE.json. Production source is never replaced by the control.

flake.lock is byte-exact from the original raw-reader experiment's archived
lock. It pins nixpkgs, Git 2.56.0 and the GHC 9.12 package set. Both benchmark
libraries compile the actual package with doCheck disabled for these copies only:
the unchanged production code already passed an independent 250-case run.
This experiment does not claim another full test-matrix pass. The control is
checked against native results for every measured dataset. The initial outer
callPackage/dontCheck setup conflict was fixed by direct package instantiation;
the corrected flake evaluation and both harness builds passed.

## Workloads

fixture.py generates new deterministic, legal v0.2.0 packed SHA-1/files DAGs.
All Roots are declared first. Each Node gets Content and a same-tree Checkpoint
with an external context, never the old q,w layout. The reader workload has
1,000 or 10,000 Nodes, each context selecting the next Node's Root. This can
cycle at the Node-label level without creating a Git commit cycle.

The shared workload gives the first Node a 256-Content ancestor chain. Its
Checkpoint selects the second Node's Root, and all other Nodes' Checkpoints
select that first Checkpoint. The last Node has three exclusive commits when
its ref is omitted. This deliberately amplifies common-ancestor traversal; it
is a controlled workload, not a claim about typical user graphs.

- inspect-oneshot / inspect-native: complete production inspectState, with the
  same validator and per-call caches; only transport capability differs. A bare
  Git double delegates each raw request to nativeGit, versus observeGit(nativeGit).
- reach-single / reach-multi: compare the two remaining-tip/exclusive-set queries
  on an already loaded validated graph. Loading is outside operation_seconds;
  query, exclusive-set and digest forcing are inside. RSS still includes loading.
- delete-legacy / delete-native: actual previewDelete, including repository reads,
  validation, plans, checks and result forcing, linked against the one-expression
  control or unchanged production library. It does not execute deletion.

Every pair checks semantic digests. Full preview reports, including plan IDs,
also match within the same fixture. Its semantic digest drops only the path-
dependent plan ID for independent regeneration. Ref hashes must remain unchanged
after every process. Git launch counts cover each Haskell measurement process,
not driver setup and audits. No permanent caches or daemon are introduced.

## Reproduction and budgets

Restore under a fresh project tmp child, preserving this layout, then run
prepare.py once. From this experiment directory, use per-command NIX_CONFIG:

```text
max-jobs = 1
cores = 1
```

```sh
timeout 120s nix flake check --no-build --no-write-lock-file -L path:./flake
timeout 300s nix build --no-link --no-write-lock-file -L path:./flake#default
timeout 120s nix run --no-write-lock-file path:./flake#default -- --stage inspect-pilot --heap-limit 1G
timeout 120s nix run --no-write-lock-file path:./flake#default -- --stage shared-pilot --heap-limit 1G
timeout 900s nix run --no-write-lock-file path:./flake#default -- --stage inspect-scale --heap-limit 1G
timeout 300s nix run --no-write-lock-file path:./flake#default -- --stage shared-scale --heap-limit 1G
```

The long build/scale bounds were explicitly authorized for this experiment.
Every stage uses three paired repeats with alternating mode order, all serial,
one Haskell capability, 1 GiB managed heap and one pack thread. Child deadlines
are 60s for pilots, 180s for reader scale and 120s for shared scale; failures stop
without retry or automatic memory expansion. A managed heap cap is not a total
RSS cap. GNU time max RSS is not summed simultaneous process RSS. OS caches are
not flushed; there is no cold-storage, CLI rendering, all-platform, exact-minimum-
Git or arbitrary-writer consistency claim. Pure and full-preview timings must
not be conflated. Results include equality digest forcing overhead.

Fresh run directories preserve every stage; large repos/imports stay outside
flake source. Agents inspect compact text/JSON only. Project staged release
manuscripts and old archives are unchanged. The user expressly excluded rerunning
historical patched-Git and batch-worktree experiments, which are not executed.
Archival assessment will select only independently necessary small recipe and
observation files, never generated packs, binaries or the entire tmp tree.
