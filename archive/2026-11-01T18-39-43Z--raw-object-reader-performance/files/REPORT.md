# Raw Git object reader performance: local measured results

Baseline project: `c1789363356cc3c7117ada31ceba6b647f6fb525`. Product source and Git state were unchanged.
Linux x86_64, locked standard Git 2.56.0 and GHC 9.12.3; the same production package definition and validator were used in both modes.

## Completed paired measurements

Each cell is the median of three runs. Times measure complete `inspectState` including result normalization, excluding CLI selection/rendering.
Current = the existing per-object native process adapter. Persistent = an experiment-only single `cat-file --batch` process adapter.

| Nodes | Checkpoints/Node | Max external fanout | Managed heap cap | Current seconds | Persistent seconds | Time ratio | Git processes current / persistent | Median max RSS MiB current / persistent |
|---:|---:|---:|---|---:|---:|---:|---:|---:|
| 10 | 1 | 0 | 512 MiB | 0.1111 | 0.0320 | 3.5x | 71 / 11 | 12.2 / 10.9 |
| 100 | 1 | 0 | 512 MiB | 1.2250 | 0.0268 | 45.7x | 611 / 11 | 14.9 / 11.5 |
| 1,000 | 1 | 0 | 512 MiB | 12.2585 | 0.1846 | 66.4x | 6,011 / 11 | 42.6 / 26.9 |
| 100 | 10 | 2 | 512 MiB | 8.5595 | 0.1106 | 77.4x | 4,211 / 11 | 31.6 / 18.7 |
| 10,000 | 1 | 0 | 1 GiB | 121.2960 | 1.7260 | 70.3x | 60,011 / 11 | 346.8 / 185.2 |

Every completed pair and repetition agreed on managed refs and retained Checkpoint digests. Caches inside the validator were fresh per invocation; filesystem caches were not flushed.
10,000-Node raw time range: current 118.7166–123.1798s; persistent 1.5787–3.2090s.

## Original 512 MiB scale attempt

The persistent adapter completed once in 2.5497s, with 11 Git processes and 185.7 MiB max RSS.
The current adapter then hit the deliberately configured 512 MiB GHC heap ceiling: exit 251 after 120.89s, max RSS 290.5 MiB. This was heap exhaustion, not a deadline or an OS OOM.
The stage stopped immediately without retry. It has no valid paired median or speedup. The later 1 GiB run is separate, explicitly authorized, and preserves the original failed result.
The managed heap ceiling is not equivalent to RSS or total concurrent memory; do not infer a minimum physical-RAM requirement from that failure alone.

## Interpretation and limits

- Per-object process creation is a measured scalability problem in the current full-check path, even with one Checkpoint and a tiny note per Node.
- A persistent raw-object transport is an effective optimization direction while retaining the current DAG and per-call caches. This experiment does not change product code or create a permanent cache.
- The candidate also changes pipe/buffer/environment/async overhead. No claim isolates all gains to fork/exec, proves a memory leak, or identifies the source of the memory difference.
- Fixtures use SHA-1/files refs, packed objects, deterministic small payloads and simple histories. The additional pilot covers longer history and direct dependencies. Dense large knowledge DAGs, large files, other platforms and cold disks were not measured.
- Only one measurement runs at a time. Nix max-jobs/cores, GHC capabilities and fixture pack threads are one. Max RSS is GNU time per-invocation accounting, not a sum across simultaneous processes.
- The experiment adapter is not production-ready: process lifecycle, stderr draining, short/malformed replies, cancellation and serialization need implementation and regression coverage before integration.

## Evidence

- [pilot raw results](runs/pilot-20261101T182250.448312Z/results.json).
- [scale512 raw results](runs/scale-20261101T182446.910300Z/results.json).
- [scale1g raw results](runs/scale-1G-20261101T183048.065324Z/results.json).

Inputs, resource policy and reproduction commands are in [README.md](README.md).
