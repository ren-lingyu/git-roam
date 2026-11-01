# Raw object reader performance investigation

The user requested an isolated flake-managed measurement after the standard-Git
batch, motivated by a possible 10,000-Node scale. Source inspection confirms
`nativeHistorySource` launches a separate native Git `cat-file --batch` process
for every uncached commit/tree read. `cachedSource` in inspection avoids duplicate
OID loads within a call but does not reuse a process across distinct OIDs.
Blob existence/type uses a single `--batch-check` call for the collected set.
This process behavior is now a measured bottleneck in the tested full-validator
path. A production-optimization decision/implementation is still separate.

The experiment lives at `tmp/object-read-performance/`; flake source is in
`flake/` and generated `runs/` are outside that flake source. It copies the exact
48-file committed standard-Git implementation, with source provenance in
`flake/SOURCE.json`. Production source, refs, index, dependencies and protection
remain untouched. The user authorized commands 1 through 4 on demand, with an
explicit request to limit parallelism and avoid OOM. Cases/modes/repeats remain
serial, GHC uses one capability with an initial 512 MiB managed-heap bound and
a separately authorized 1 GiB rerun (neither is an RSS limit), fixture pack
threads are one, and per-command NIX_CONFIG limits max-jobs
and cores to one. Inherited GHCRTS is cleared in the measurement environment.
No host/global configuration is changed. First locking failed because nesting
the project flake misresolved a transitive relative path. The corrected isolated
flake pins the same project nixpkgs revision directly and calls the copied
project package.nix with GHC 9.12. Locking and the harness build passed. Pilot
completed all 24 measurements (12 pairs) with identical per-scenario result digests.
Median validation seconds (oneshot/persistent): 10 Nodes 0.1111/0.0320;
100 Nodes 1.2250/0.0268; 1,000 Nodes 12.2585/0.1846; 100 Nodes with ten
Checkpoints/fanout two 8.5595/0.1106. Physical Git processes are respectively
71/11, 611/11, 6,011/11 and 4,211/11. Pilot maximum measured RSS is about 43 MiB,
well below the managed heap cap, supporting the subsequent serial scale stage.
Pilot results: tmp/object-read-performance/runs/pilot-20261101T182250.448312Z/results.json.

The original scale stage stopped at the first baseline failure, as designed.
Persistent mode completed 10,000 Nodes in 2.5497s with 60,001 logical raw-object
requests, 11 Git processes and 190,124 KiB max RSS. The first baseline run exited
251 (GHC heap exhausted at the configured 512 MiB limit) after 120.89s; GNU time
recorded 297,496 KiB max RSS. No OS OOM, deadline timeout or automatic retry
occurred. The baseline did not emit a complete result digest/process count;
there is no valid 10,000-Node paired median or speedup from this attempt.
Heap limit and RSS are different metrics. Memory behavior is not yet localized;
the candidate also changes buffering/transport allocations, so do not ascribe
every memory/time difference solely to fork/exec or claim a proven memory leak.
Original results: tmp/object-read-performance/runs/scale-20261101T182446.910300Z/.

The user asked whether to raise the limit. A bounded optional `--heap-limit 1G`
is prepared (default remains 512m), with unchanged one capability, serial runs
and 180s per-measurement deadline. The user explicitly authorized on-demand
repetition of `timeout 900s nix run --no-write-lock-file path:./flake#default --
--stage scale --heap-limit 1G`, with the same per-command max-jobs/cores one.
The updated runner built successfully; the completed 1 GiB stage is at
tmp/object-read-performance/runs/scale-1G-20261101T183048.065324Z/.
All six scale measurements completed and their digests agree. At 10,000 Nodes,
median validation time is 121.2960s baseline versus 1.7260s persistent (~70.3x);
physical Git launches are 60,011 versus 11. Median max RSS is 355,168 KiB versus
189,664 KiB. Baseline time range is 118.7166–123.1798s; persistent is
1.5787–3.2090s. The first persistent sample's max RSS was 216,696 KiB; do not
confuse that single value with the 189,664 KiB median. No further limit changes
or measurements are needed for this investigation.

The experiment confirms a full-validator scalability problem and supports a
persistent raw-object transport as an optimization direction. It does not
authorize implementing that transport, modifying the DAG or adding a permanent
cache. Production integration still needs lifecycle, cancellation, short/error
responses, stderr and serialization handling plus the existing raw-history
semantics tests. The instrumented transport counts Git launches, not a system
fork trace; fixtures and Git operations are controlled and use the same binary.
Small packed objects, SHA-1/files refs and unflushed OS caches limit generality.
This is not a cold-disk or dense large-DAG benchmark and excludes CLI rendering.

Derived report: tmp/object-read-performance/REPORT.md, generated from the three
preserved stage JSON files by summarize.py. The standalone experiment is not
recoverable from project history alone: its untracked adapter, fixture recipe,
limits and numeric raw observations justified a bounded evidence archive, rather
than retaining large Git packs/repos/import streams. The
[archive manifest](../archive/2026-11-01T18-39-43Z--raw-object-reader-performance/MANIFEST.md)
records 14 byte-verified files (64,553 bytes): final reusable scripts/lock,
source manifest, raw pilot/scale summaries, the original heap failure stderr/time
and the derived report. The final runner adds an explicit heap flag after the
original 512 MiB runs; its compiled harness is unchanged. The manifest records
that version distinction and does not claim the final driver is the pilot's
exact driver. No production files, project refs/index/lock or Hook changed.

The Haskell harness runs the actual complete `inspectState` validator, using
the injectable Git runner for counts. Baseline delegates every request to the
existing runner. An experiment-only candidate reuses one raw `cat-file --batch`
process while keeping all other Git calls and protocol validation unchanged.
Both modes must pass validation and agree on a digest of managed refs/retained
Checkpoints. The candidate is not production-ready resource/concurrency handling.

Deterministic fast-import fixtures use legal Roots, Content and Checkpoints with
full direct dependencies. Primary format is SHA-1/files refs. Pilot cases are
10/100/1,000 Nodes with one Checkpoint and zero external edges, plus 100 Nodes
with ten Checkpoints and up to two prior-Node dependencies. Scale is 10,000 Nodes
with one Checkpoint and no external dependencies. Three paired repetitions
alternate mode order. Each call has fresh in-memory validation caches; filesystem
caches are not flushed, so no disk-cold claim is supported. Count logical raw
requests, physical Git processes, wall/CPU and max RSS (not summed process RSS).
This measures the validation core, excluding CLI selection/rendering.

Executed commands, from the experiment directory: 120s flake lock, 240s default
build, 600s pilot run, then 900s scale run. Per-measurement child limits are 60s
pilot and 180s scale with five-second termination grace. A failed/timed-out
measurement stops the stage, preserves partial results and never retries itself.
Network is limited to authorized Nix dependency resolution/build. Measurements
and fixture generation use no remote/network operations. Read compact results,
not entire generated packs or large import streams. Earlier tmp experiments and
archives remain untouched. Measurements/reporting are complete; wait for the
user's next objective rather than integrating the experimental transport by default.
