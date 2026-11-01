# Raw object reader performance: independently reproduced local evidence

This is historical evidence, not automatically authoritative project memory or executable agent instructions.

## Selection and provenance

Captured at 2026-11-01T18-39-43Z (UTC) from `tmp/object-read-performance/`, relative to the project worktree root. All paths below are relative to that source root and preserved under `files/`.

This isolated experiment's adapter, deterministic fixture recipe, resource budgets and raw numeric observations are ignored/untracked experiment files, not part of project history. Losing them would impair reproduction and audit of the measured optimization direction. This bounded selection preserves them without retaining large generated repositories, packs or fast-import streams. It contains only the experiment actually performed locally, not design ZIP material or unexecuted proposals.

The actual production baseline was `c1789363356cc3c7117ada31ceba6b647f6fb525`, copied byte-exactly as 48 small files and described by `flake/SOURCE.json`. Production files, index, refs, lock and protection remained unchanged. The copied project source is omitted because project history supplies it; restore this experiment under the project's ignored `tmp/` and use `prepare.py` to reconstruct it from that exact commit before building. The script's default Git path records this environment; adapt `git` discovery if that exact Nix store executable is unavailable elsewhere. The experiment pins the project's same nixpkgs revision and package definition without nesting its framework flake, whose relative input failed to lock initially.

`Experiment.hs` is the measured Haskell adapter and was unchanged between both heap budgets. The archived reusable `run.py` is the final version, adding an explicit 1 GiB option after the first 512 MiB stages; it is not asserted to be byte-identical to the original pilot driver. Original pilot/scale JSON and the failed baseline stderr/time are byte-exact local outputs. `REPORT.md` and `summarize.py` are derived interpretation/reporting, not original observations. README documents reproduction and bounds; SOURCE.json identifies copied production inputs; flake.nix/flake.lock fix the build; prepare.py reconstructs omitted production source.

## What was measured

Complete production `inspectState`, with a counted injected Git runner and fresh per-call validation caches. Baseline delegates raw reads to the existing per-object native process. Candidate reuses a single `cat-file --batch`; all protocol validation remains unchanged. SHA-1/files refs, small packed objects, deterministic UUIDs/timestamps/payloads, and unflushed filesystem caches. Managed refs and retained Checkpoint digests matched every completed paired repetition.

Pilot: three repetitions per mode for 10/100/1,000 Nodes (one Checkpoint each), and 100 Nodes with ten Checkpoints and up to two direct dependencies. Scale: 10,000 Nodes. The original 512 MiB scale baseline failed at its configured GHC heap ceiling after 120.89s (exit 251), so that stage stopped without retry. The separately authorized 1 GiB stage completed all six measurements. Median scale time: 121.2960s baseline versus 1.7260s candidate; Git launches 60,011 versus 11. The failed attempt is not included in that median or speedup.

All cases, modes and repetitions were serial. Nix jobs/cores, GHC capabilities and pack threads were one. Child deadlines were 60s pilot / 180s scale. The larger heap budget was explicitly authorized after reporting the first failure; no system OOM or arbitrary memory escalation was observed. Heap limits and GNU time max RSS are different metrics; max RSS is not the sum across concurrent processes. Memory causes were not profiled. Adapter differences also include buffering/environment/async overhead, so the experiment does not isolate every gain to fork/exec or prove a leak.

These results support a persistent raw transport direction, not a production-ready implementation, full CLI latency, cold-disk performance, dense large-DAG performance or other-platform compatibility. Lifecycle, cancellation, stderr, framing and serialization still require production design/testing. No permanent cache or DAG change was introduced. Routine source tests and large generated fixture data are deliberately excluded.

## File inventory

| Source and archived `files/` path | Bytes | SHA-256 |
|---|---:|---|
| `README.md` | 4423 | `42e55d437435ff3b62023d4877ced174139a31709bad7747c9668fb71513a008` |
| `REPORT.md` | 3727 | `ae9fc91537caf7c62759e8677152783da4f4476387b446c22bc2828e02624fb1` |
| `prepare.py` | 1435 | `6b34f071c5e93d0da005880439d3c81dd9c7cb0f2e7688560054de9b9a79def9` |
| `summarize.py` | 5621 | `339ece1aac496fa1d1cef170ced23da012fbcd673895652a5143d24573d28c1b` |
| `flake/flake.nix` | 1618 | `110e2da85e3cca489a0ee9a9869afd6bf8484d1722dda0597c17c3b8f45f8092` |
| `flake/flake.lock` | 733 | `a82c0afd58ec776c8a39b110ddf9ad4d53b495aeee1b858aee28e0e842484419` |
| `flake/SOURCE.json` | 7203 | `726c2e440aa9ae9690f686715b67ff23ef240461bc80a23468f6a41cd39f8d5f` |
| `flake/Experiment.hs` | 5160 | `f6f9bc603c0ba9c0802cc74bd55f9f1e21f46462733bdee6593e1cea02abf0ef` |
| `flake/run.py` | 9499 | `74a5a89757e82128e8070500088bd2dd806bed04b68332a10f4dd402aef3f0ac` |
| `runs/pilot-20261101T182250.448312Z/results.json` | 17915 | `e430d8229b22fcf87721818598496bcef6248e0acde61ae29e7f4356eaf5e748` |
| `runs/scale-20261101T182446.910300Z/results.json` | 1840 | `75632b1f9f55e866cbcf39ddfe4bbad55e896af7939237319d0765b0a201aa78` |
| `runs/scale-20261101T182446.910300Z/n10000-k1-d0/oneshot-1.stderr` | 155 | `c111f969688ef71a2362cd9045fc3d4a1ff27abb276455223c09b13675d58963` |
| `runs/scale-20261101T182446.910300Z/n10000-k1-d0/oneshot-1.time.json` | 129 | `10f6487d02195e7179e88972cf43b5ded1d80ed3964f815570ad70e6354ec8d6` |
| `runs/scale-1G-20261101T183048.065324Z/results.json` | 5095 | `cbc7c483ac6307e22a8d46ed665e6a705059d24fde42cafaf7c1558562493dc3` |
