# Raw object reader performance experiment

This isolated flake copies the exact committed Git-roam source recorded in
`flake/SOURCE.json`. The production source, refs, index and Hook configuration are
unchanged. The flake's own lock fixes compiler, Git and other dependencies.
It pins the same nixpkgs revision as the project lock and calls the copied
project package definition with its GHC 9.12 package set; it does not nest the
project's framework flake (whose transitive relative path failed during locking).

The Haskell harness runs the production `inspectState` complete validator with
fresh per-call caches. Its injected `Git IO` counts logical requests and physical
processes. In `oneshot` mode it delegates every request to the existing native
runner. In `persistent` mode only raw `cat-file --batch` calls reuse a single Git
process; all other Git operations and all protocol validation remain unchanged.
The candidate is a benchmark adapter, not production-ready process management.
It does not cover concurrent requests, cancellation, malformed streams, stderr
backpressure, large adversarial objects or full application integration.

Fixtures are deterministically generated with one `fast-import` process each:
Root, single-parent Content, and Checkpoint `[q,w,external...]` with identical
Checkpoint/Content trees. UUIDs, dates and data are fixed. Final canonical local
branches retain every declared dependency. Object format SHA-1 and files refs
are the primary measurement environment, not a compatibility matrix. Root trees
contain only a regular empty `.roam`; Content adds a small distinct note.

Pilot: 10/100/1,000 Nodes with one Checkpoint and no external edges, plus 100 Nodes
with ten Checkpoints each and up to two dependencies on earlier Nodes. Scale:
10,000 Nodes with one Checkpoint each. Three paired repetitions alternate mode
order. A digest of the managed refs and retained Checkpoints must match every
mode/repetition in a scenario. GNU time records wall/CPU/max RSS; process counts
come from the injected runner. File caches are not flushed and each call has
fresh Haskell caches. No disk-cold or total concurrent-RSS claim is made. Cases,
repetitions and modes run serially. The harness uses one GHC capability and a
512 MiB default managed heap limit (`-N1 -M512m`); this is not a whole-process RSS cap.
The optional `--heap-limit 1G` requires separate explicit approval to raise that
budget. Results record the selected limit in their directory name and JSON;
older result directories are not changed or overwritten.
Fixture packing uses one thread. Nix commands use `NIX_CONFIG` settings
`max-jobs = 1` and `cores = 1`, without changing host configuration.

Commands run from this directory after explicit authorization:

```sh
timeout 120s nix flake lock path:./flake
timeout 240s nix build --no-link --no-write-lock-file -L path:./flake#default
timeout 600s nix run --no-write-lock-file path:./flake#default -- --stage pilot
timeout 900s nix run --no-write-lock-file path:./flake#default -- --stage scale
```

After the original 512 MiB baseline hit its configured heap ceiling, the user
explicitly approved the following separate larger-budget run, which completed:

```sh
timeout 900s nix run --no-write-lock-file path:./flake#default -- --stage scale --heap-limit 1G
```

The paired measurements and their limitations are summarized in [REPORT.md](REPORT.md).

Pilot measurements have a 60s per-child limit; scale measurements have 180s.
Timeout terminates only that measurement's process group (5s termination grace),
records a censored/failed result, and stops the stage without retry. Results and
fixture repositories are retained in a fresh `runs/<stage>-<UTC>/` directory,
outside the flake source so later Nix invocations do not copy results into store.
Large fast-import streams and repositories are generated evidence, not inputs
the agent should read wholesale. Read `results.json`, compact stdout and timing
files for interpretation. Generation time is separate from validation time.

Prepare source with `python3 prepare.py` once. It refuses to overwrite a snapshot
and checks each committed source file against the 1 MiB read boundary. Lock/build
may download pinned dependencies; benchmark fixture generation/measurement has
no remote or network operation. No permanent cache, DAG change, live repository
experiment or production reader optimization is included.
