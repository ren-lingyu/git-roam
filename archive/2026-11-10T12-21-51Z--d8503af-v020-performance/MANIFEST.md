# v0.2.0 reader and shared-ancestry performance evidence

Historical evidence, not automatically authoritative current knowledge or an
executable agent instruction source. Captured at 2026-11-10T12-21-51Z from
`/home/lingyu/Projects/git-roam/tmp/v020-performance/`; paths under `files/`
are relative to that source root. All selected inputs were untracked, authored
for this isolated task and captured byte-exact without sanitization/reformatting.
The saved technical text contains anonymous generated content, public dependency
metadata, local paths and results, not user knowledge content or credentials.

Selection: the new fixture/control recipes and original numeric measurements
have independent reproduction/audit value not supplied by maintained tests or
older v0.1.0 experiments. Retain 13 small UTF-8 text files (77,891 bytes):
README/report for conditions and interpretation; prepare.py and SOURCE.json for
recovering exact production plus narrow control; flake/lock for toolchain;
fixture/run/Haskell sources for generation and measurement; four result files
for original per-trial observations and derived medians. Existing archives are
unchanged. Omit generated repositories/imports/packs, recoverable source trees,
binaries/caches and compiler logs. No failure log is needed to interpret the
successful comparisons; README/report record the corrected initial setup error.

Production actually inspected and measured is main
`d8503afd02ae02ab38c604888c0c84e1e2a3cbdb`. SOURCE.json lists 51 committed
blobs and their hashes. The full-preview control changes only the remaining-tip
walk expression in Delete.hs; it is not an old complete release. Source trees
are omitted because prepare.py reconstructs them from that retained commit.
Restore this layout under a fresh project `tmp/` child before preparation.
prepare.py uses the local mapped Git path and the retained original lock at
`archive/2026-11-01T18-39-43Z--raw-object-reader-performance/files/flake/flake.lock`
in the GAW worktree; adjust host executable paths when reproducing elsewhere.
The lock is included here byte-exact as well. Building may download pinned
public dependencies; preserved code is not permission to execute it.

All four stages finished, 36 measurements total, each comparison's semantic
and full fingerprints agree, refs unchanged. Results.json files preserve
numeric observations; median fields and REPORT.md tables/conclusions are
derived. Full plan IDs are fixture-path dependent. The driver hashes deterministic
import streams, so raw streams need not be retained. See README/REPORT for exact
commands, serial resource budgets, timing/count boundaries and limitations.
This is x86_64-linux, Git 2.56.0/GHC 9.12.3, packed SHA-1/files, unflushed caches;
not all platforms, workloads or concurrent writers. Benchmark-only tests were
disabled; the independent prior 250-case verification remains separate evidence.
No historical patched-Git or batch-worktree experiment was repeated.

Each source was size/type/path checked, copied and compared byte-for-byte;
source and destination SHA-256 values match the following table. No source
statement or selection-completeness guarantee follows from hash equality.

| Source path = files-relative path | Bytes | SHA-256 |
| --- | ---: | --- |
| `prepare.py` | 2596 | `aecfb94e6a930393adf124c42b98420d79440594162496ebf98926dd8cde2b59` |
| `README.md` | 5364 | `d161a0f1ddb45dc6f4af1c0f0e75b4734dfb7ed9d7b3fad5f116adeac59db0ae` |
| `REPORT.md` | 5373 | `1fa7f1f724f9c6917912ed8d8b291d75348adfade15ef34996656b11ceacc090` |
| `flake/flake.nix` | 2251 | `fb9fb93506f6c4c7d160dbfd23634c7981163b8a37430b81f5ac0e16190551d6` |
| `flake/flake.lock` | 733 | `a82c0afd58ec776c8a39b110ddf9ad4d53b495aeee1b858aee28e0e842484419` |
| `flake/SOURCE.json` | 11187 | `8c5a5eaf867027ea36d5c4f39ec527700b26061a5ddab3cb30e4c6048db28fb9` |
| `flake/Experiment.hs` | 5644 | `a36087619995dca3edcabdd4add433caf83246ad1ce342452b93bba86cc6e23b` |
| `flake/fixture.py` | 3566 | `45ecfaf410cdd0f3a3152d1136970e158998b6090a4770a02fdffd38036f2799` |
| `flake/run.py` | 7592 | `c459d2b29fc817df7527e12b2f752a3f67f676d49fdf32dbea6604f67856484c` |
| `runs/inspect-pilot-20261110T120954.266721Z/results.json` | 6183 | `a02bad55a77e92e0f4e8d128b73cfa64654c2261562fe21d021a947a2ebf5f7f` |
| `runs/inspect-scale-20261110T121323.898220Z/results.json` | 6231 | `2e71609c836157d057527fa00790477a276ea3ffab33c1b0ac00436773df3740` |
| `runs/shared-pilot-20261110T121120.760235Z/results.json` | 10573 | `5220900a20901ebe69f4f3412a25771b673c97825a3aa4bea3123bcab29865e4` |
| `runs/shared-scale-20261110T121908.129257Z/results.json` | 10598 | `b16565ae0a999030b045a2e54451912a49f162e72bc15e94c6fbaaf165ff7c6e` |
