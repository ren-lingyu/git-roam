# v0.2.0 performance verification — 2026-11-10

All 36 measurements completed successfully. Per comparison group, semantic
results and full result fingerprints agree across modes and all three repeats.
Managed-ref digests are unchanged before/after every measurement. Both source
copies still match the recorded production/control hashes.

Production baseline: d8503afd02ae02ab38c604888c0c84e1e2a3cbdb.
Git 2.56.0, GHC 9.12.3, x86_64-linux; pinned flake. Each row is the median of
three serial measurements. RSS is the median of per-process GNU time maximum
RSS, not a simultaneous process-tree memory total. The 1 GiB managed heap cap
is not an operating-system memory limit. Observed largest max RSS was below
651 MiB; no timeout or OOM occurred in the measured stages.

| Nodes | Mode | Seconds | Git launches | Max RSS MiB |
| ---: | --- | ---: | ---: | ---: |
| 1,000 | inspect-oneshot | 9.515691 | 6,011 | 52.71 |
| 1,000 | inspect-native | 0.198297 | 11 | 38.34 |
| 10,000 | inspect-oneshot | 89.570110 | 60,011 | 461.30 |
| 10,000 | inspect-native | 1.706268 | 11 | 412.99 |
| 1,000 | reach-single | 0.098355 | 11 | 36.27 |
| 1,000 | reach-multi | 0.007795 | 11 | 26.84 |
| 1,000 | delete-legacy | 0.554772 | 39 | 74.93 |
| 1,000 | delete-native | 0.466648 | 39 | 52.60 |
| 10,000 | reach-single | 0.936478 | 11 | 240.75 |
| 10,000 | reach-multi | 0.060132 | 11 | 199.79 |
| 10,000 | delete-legacy | 8.174572 | 39 | 649.86 |
| 10,000 | delete-native | 4.802624 | 39 | 484.84 |

## Interpretation

At 10,000 Nodes, persistent raw reading reduces full inspection from 89.570110s
to 1.706268s (52.49x), and Git launches from 60,011 to 11. Raw batch processes
fall from 60,001 to one. The corresponding 1,000-Node inspection is 48.0x faster.
The process-start bottleneck remains resolved in the production v0.2.0 reader.

On the shared-ancestor workload, the 10,000-Node loaded-graph query improves
from 0.936478s to 0.060132s (15.57x); the actual full deletion preview improves
from 8.174572s to 4.802624s (1.70x). At 1,000 Nodes the respective improvements
are 12.62x and 1.19x. Do not substitute the pure-query ratio for end-to-end
preview performance. Preview still performs validation, repository I/O and
multiple object-reading sessions: both versions start 39 Git processes, with
three persistent batch readers. Query timing starts after graph loading; RSS
covers loading too. Each preview identifies exactly three exclusive commits.

The reader control changes only transport capability; its validator/cache are
identical. The deletion control changes only the remaining-tip expression back
to singleton traversals plus union. It is not a benchmark of a previous complete
release. Pure query uses the current shared validator and graph. Control and
native preview reports, including path-dependent plan IDs, match within each
fixture. Semantic fingerprints omit only that plan ID to allow regeneration.

## Reproducibility and limits

See README.md, prepare.py and flake/SOURCE.json. Restore these selected recipes
under a fresh project tmp child; prepare.py recovers the retained production
commit and narrow control and copies the previously archived lock. Run the
listed flake commands with max-jobs=1 and cores=1. Generated import streams are
deterministic and their hashes are in each results.json. Sources and fixtures
are new v0.2.0 context DAGs, not the old v0.1.0 fixture bytes. Production source,
index, refs, protection, and existing archives remain unchanged.

The generated graphs use packed SHA-1/files, small content, one Checkpoint per
Node; shared cases have a 256-Content anchor. They deliberately expose shared
ancestry and do not represent all workloads or long Checkpoint histories.
OS caches were not flushed. There is no cold-storage or strict timing threshold
claim. All timings include result-fingerprint forcing; query excludes loading.
Instrumented Git counts exclude fixture setup and driver ref audits. Actual
ref deletion, GC, worktree operations, CLI rendering, other platforms/backends,
minimum Git compatibility and arbitrary concurrent writers were not benchmarked.
No historical patched-Git or batch-worktree experiment was rerun.

Benchmark-only package copies disable their test phase. The independent prior
14-suite/250-case production run is separate evidence; this experiment does not
claim an additional full correctness-suite pass. Initial flake instantiation
failed before measurement and was corrected; the corrected flake evaluation and
both compiled harnesses succeeded. All completed repeats, including timing
outliers, remain in the compact result files; medians do not discard repeats.

## Archival assessment

Retain a new bounded snapshot: recipes, lock, exact production/control source
manifest, this report and four compact result files. These new untracked
controls, fixture construction and numeric observations have independent audit
and reproduction value beyond maintained source/tests and older experiments.
Omit recovered production trees, generated repositories/imports/packs, binaries,
caches and complete compiler logs: project history and recipes reproduce them,
and retaining them adds little evidence. Original per-trial numeric observations
are in results.json; its median fields and this interpretation are derived.
The snapshot is historical evidence, not an executable instruction source.
