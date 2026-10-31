# Independent local experiment: Git worktree batch registration

Historical evidence, not automatically authoritative project knowledge or
executable agent instructions. Archiving these scripts does not authorize
executing them. This record covers only the two experiments actually performed
locally in this session; it does not archive the supplied design history or
validate earlier experimental claims.

Capture time: 2026-10-31 06:58:49 UTC.

## Purpose and selection

Preserve the exact methods, locked inputs, applied patch variants, measured
observations, and necessary failure/correction evidence for independent
reproduction and audit of worktree batch registration. Current memory alone
cannot reconstruct these inputs or the 60 original timed samples. The ignored
experiment is not stored in application project history, and no earlier archive
already preserved this evidence.

The 29 selected files/derivatives total 113879 bytes. They include the
two independently usable flake configurations, their scripts/patches/locks,
raw JSON measurements, local reports, two short original observation logs,
and six explicitly labelled excerpts. Small script duplication keeps each
flake's relative inputs usable. Routine compiler output and redundant details
were omitted rather than preserving about 856 KiB of complete logs.

## Experiment and observed outcome

The local question was whether the supplied cumulative batch method works and
reduces no-checkout registration cost, and whether it can be packaged by merely
appending patches to nixpkgs Git without independently acquiring Git sources.

- Phase 1: Git 2.54.0 source commit
  `94f057755b7941b321fd11fec1b2e3ca5313a4e0`, with the three patch files unchanged
  from the supplied ZIP. Direct source-override compilation initially failed
  HTTP linking because curl-config was unavailable. `NO_CURL=1` was applied to
  the three local-only comparison variants. Their available upstream suites
  reported 1026 files and 28587 tests, PASS, with unsupported features skipped.
- Phase 2: `pkgs.gitMinimal` (2.56.0) from the locked nixpkgs, retaining its
  source, version, build flags, and original package patches. Only the experiment
  patches were appended. Initially they did not apply; adapting get_worktrees
  and check_branch_ref to pass the_repository fixed this. These are the only
  patch-text changes from phase 1. Patched and list-reuse builds reported
  1043 files and 29449 tests, PASS; the baseline was unchanged nixpkgs Git.
- Both phases passed the original smoke and 18 safety cases each (nine per ref
  backend), including preflight rejection, occupied branches, existing user data,
  and injected failures during/after registration with metadata/lock checks.
- Each phase recorded 30 validated timing samples: three variants at 700
  worktrees and final batch at 1500/5000, on files and reftable, three repeats.
  Measurements exclude setup, validation and cleanup, and perform no checkout.

Both phases lock nixpkgs commit
`885ba4d038f10c3d17d7a92e8c3cc185b99c9158`, with narHashes in their respective
lockfiles. The observed host was Linux x86_64, Nix 2.34.9. Timings are local
observations, not deterministic build outputs or portable performance claims.
The detailed local table/method is in
[REPRODUCTION.md](files/tmp/worktree-batch-reproduction/REPRODUCTION.md).

## Source roots and provenance

The source root for all paths below is the Git Roam project worktree
`/home/lingyu/Projects/git-roam`; the assessed experiment source is its ignored
`tmp/worktree-batch-reproduction/`. The archive root is the formal GAW workspace's
declared `archive/`. Under `files/`, original project-relative paths are preserved.
Excerpt filenames add `.excerpt` before `.log`, with mappings and ranges below.

The experiment files were produced/used during this local reproduction, not
read from an application project commit. The original patch bytes were compared
to these ZIP members: `git-roam-worktree-experiment/patches/0001-reuse-worktree-list.patch`,
`0002-experimental-batch-add.patch`, and
`0003-safe-batch-validation-and-rollback.patch` under the same member directory.
The supplied ZIP SHA-256 is `d63547595d2de0bed3b4a3745c173a470a1deaea999a7d7e4a80f9ad44b19485`. Its bytes, consolidated design
history, earlier timings/experiments, and unexecuted proposals are not captured.
ZIP identity is only provenance for patch bytes actually used locally.

The source `MANIFEST.json` is preserved as the original local experiment's
inventory/fingerprints. It lists more files than this selective capture and
is not the archive's inventory; this MANIFEST.md is the archive inventory.
The unchanged source README/report refer to some full logs and source copies
not captured here. Read those references in their original local-run context;
use the selected originals/excerpts mapped here for archived observations.
Only the necessary original patches from phase 1 are included, not the supplied
experimental README's old benchmark claims or a complete source bundle.

No non-first project parent is selected: these are independent experimental
inputs and results, not tests against the application's main commit. Source
pins and content digests establish bounded provenance without importing
unrelated source history. No captured project HEAD is asserted as the origin
of these formerly untracked files.

## Selected bytes

SHA-256 below identifies each saved file's bytes. Originals were copied without
re-encoding, formatting, or normalization. Excerpts add a source/range header
and separators but preserve selected original line bytes. No content redaction
was required after contextual screening; omitted log lines are selection, not
evidence that every possible sensitive string was proven absent.

| Source (project-root-relative) | Archived path (snapshot-relative) | Form | Bytes | Archived SHA-256 |
| --- | --- | --- | ---: | --- |
| `tmp/worktree-batch-reproduction/flake.nix` | [files/tmp/worktree-batch-reproduction/flake.nix](files/tmp/worktree-batch-reproduction/flake.nix) | original bytes | 2001 | `c216d92afc8f30b4fee0a0ed1d3652459b961a7cdccf54b32c8d273edebdcbda` |
| `tmp/worktree-batch-reproduction/flake.lock` | [files/tmp/worktree-batch-reproduction/flake.lock](files/tmp/worktree-batch-reproduction/flake.lock) | original bytes | 593 | `5ca70162b37bdcdae81fcf61322501214c43e48b576889e7be403be69c15c824` |
| `tmp/worktree-batch-reproduction/smoke.sh` | [files/tmp/worktree-batch-reproduction/smoke.sh](files/tmp/worktree-batch-reproduction/smoke.sh) | original bytes | 1303 | `815e826ae7515ca9ca1df9607c4e386cb00a1ea5999e71f2022443afdbc470df` |
| `tmp/worktree-batch-reproduction/benchmark.py` | [files/tmp/worktree-batch-reproduction/benchmark.py](files/tmp/worktree-batch-reproduction/benchmark.py) | original bytes | 4394 | `7f20023eb71c75fcda082b51f07e459079f6e1aae740144acf5358bc58fd4c62` |
| `tmp/worktree-batch-reproduction/safety.py` | [files/tmp/worktree-batch-reproduction/safety.py](files/tmp/worktree-batch-reproduction/safety.py) | original bytes | 3690 | `a351461c0ac8cc626332e4bb91966d77b0eada71d9ae0fe7d5a10f4c8b189654` |
| `tmp/worktree-batch-reproduction/results.json` | [files/tmp/worktree-batch-reproduction/results.json](files/tmp/worktree-batch-reproduction/results.json) | original bytes | 6813 | `9423a26d23e32fd7d9a6662ae90175e43038d976e056be6095ea2a32e139f48d` |
| `tmp/worktree-batch-reproduction/patches/0001-reuse-worktree-list.patch` | [files/tmp/worktree-batch-reproduction/patches/0001-reuse-worktree-list.patch](files/tmp/worktree-batch-reproduction/patches/0001-reuse-worktree-list.patch) | original bytes | 2062 | `e8e9ad4a27d487870522e73d50e47caae8e0b002690bff5a5c16c9bbacb489e8` |
| `tmp/worktree-batch-reproduction/patches/0002-experimental-batch-add.patch` | [files/tmp/worktree-batch-reproduction/patches/0002-experimental-batch-add.patch](files/tmp/worktree-batch-reproduction/patches/0002-experimental-batch-add.patch) | original bytes | 6106 | `c64e804e90c35d98061ff954ee2e2d27ce83167e692f22dc9481dbdf7e78b7cc` |
| `tmp/worktree-batch-reproduction/patches/0003-safe-batch-validation-and-rollback.patch` | [files/tmp/worktree-batch-reproduction/patches/0003-safe-batch-validation-and-rollback.patch](files/tmp/worktree-batch-reproduction/patches/0003-safe-batch-validation-and-rollback.patch) | original bytes | 12011 | `b4bc35e0f5331841f292ef6174eebbdfdca688649999ddd4b9bb6ac69bb0afc5` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/flake.nix` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/flake.nix](files/tmp/worktree-batch-reproduction/phase1-fixed-source/flake.nix) | original bytes | 2470 | `e0e81c90bc573d60d2a199a5c4c46034a0e3196c058a448512f4f73c5da10014` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/flake.lock` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/flake.lock](files/tmp/worktree-batch-reproduction/phase1-fixed-source/flake.lock) | original bytes | 1102 | `00dc8af77febef1e4513d78dcd11d6fc542eda9849a745f3f175352d96353c01` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/smoke.sh` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/smoke.sh](files/tmp/worktree-batch-reproduction/phase1-fixed-source/smoke.sh) | original bytes | 1303 | `815e826ae7515ca9ca1df9607c4e386cb00a1ea5999e71f2022443afdbc470df` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/benchmark.py` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/benchmark.py](files/tmp/worktree-batch-reproduction/phase1-fixed-source/benchmark.py) | original bytes | 4394 | `7f20023eb71c75fcda082b51f07e459079f6e1aae740144acf5358bc58fd4c62` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/safety.py` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/safety.py](files/tmp/worktree-batch-reproduction/phase1-fixed-source/safety.py) | original bytes | 3690 | `a351461c0ac8cc626332e4bb91966d77b0eada71d9ae0fe7d5a10f4c8b189654` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/results.json` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/results.json](files/tmp/worktree-batch-reproduction/phase1-fixed-source/results.json) | original bytes | 6855 | `cfbeb88d5245f4cc7f4bb505205e4f6cbb7f89b59e73a81fbdcd8ca47ed80b83` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0001-reuse-worktree-list.patch` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0001-reuse-worktree-list.patch](files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0001-reuse-worktree-list.patch) | original bytes | 2004 | `0153ce562ed759fac0d5ce67939535f2654db414d6fba5c64f22a47ed12e38d4` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0002-experimental-batch-add.patch` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0002-experimental-batch-add.patch](files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0002-experimental-batch-add.patch) | original bytes | 6032 | `c0a69822417b33c8db956b325efca480945c49a11701bd52910880bb3d9df833` |
| `tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0003-safe-batch-validation-and-rollback.patch` | [files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0003-safe-batch-validation-and-rollback.patch](files/tmp/worktree-batch-reproduction/phase1-fixed-source/patches/0003-safe-batch-validation-and-rollback.patch) | original bytes | 11967 | `d043fa040a0fe10f26cc5abca356cdf0f56d1d19ae12200b1f4ab195ecdf3f6b` |
| `tmp/worktree-batch-reproduction/README.md` | [files/tmp/worktree-batch-reproduction/README.md](files/tmp/worktree-batch-reproduction/README.md) | original bytes | 2542 | `315479bd07f02dc63954f14a3015f8fdaf250052571c1c2e486c57279f0138a3` |
| `tmp/worktree-batch-reproduction/REPRODUCTION.md` | [files/tmp/worktree-batch-reproduction/REPRODUCTION.md](files/tmp/worktree-batch-reproduction/REPRODUCTION.md) | original bytes | 6946 | `c61238c4554ccb8d2c6b8acdc9405e15d651fcbb4ce8a9cc13606b2892e3b4bd` |
| `tmp/worktree-batch-reproduction/MANIFEST.json` | [files/tmp/worktree-batch-reproduction/MANIFEST.json](files/tmp/worktree-batch-reproduction/MANIFEST.json) | original bytes | 4337 | `456d8b8d2641d4a3bb37d6e68769847dd4757e3030151a7075703b8416a9d7aa` |
| `tmp/worktree-batch-reproduction/logs/check-01.log` | [files/tmp/worktree-batch-reproduction/logs/check-01.log](files/tmp/worktree-batch-reproduction/logs/check-01.log) | original bytes | 871 | `367dba6019310a6585095e61ab6f4ec8975a3df7fc54af545e58b45a0312154f` |
| `tmp/worktree-batch-reproduction/logs/check-03-safety.log` | [files/tmp/worktree-batch-reproduction/logs/check-03-safety.log](files/tmp/worktree-batch-reproduction/logs/check-03-safety.log) | original bytes | 2645 | `cc90488451f0eed9554ad116722ba91cdb69fb88ed18fa89f644118e0728f89a` |
| `tmp/worktree-batch-reproduction/logs/build-01.log` | [files/tmp/worktree-batch-reproduction/logs/build-01.excerpt.log](files/tmp/worktree-batch-reproduction/logs/build-01.excerpt.log) | excerpt derivative | 1329 | `e50b641c370fbc7059c368e8a8a8dc18d38d5f420320ced0e07098bf340ff090` |
| `tmp/worktree-batch-reproduction/logs/build-02.log` | [files/tmp/worktree-batch-reproduction/logs/build-02.excerpt.log](files/tmp/worktree-batch-reproduction/logs/build-02.excerpt.log) | excerpt derivative | 1936 | `5656665419964c983abb668b0b03ca44ee9cbd897a846196ccbbb437eb9ce534` |
| `tmp/worktree-batch-reproduction/logs/check-02-benchmark.log` | [files/tmp/worktree-batch-reproduction/logs/check-02-benchmark.excerpt.log](files/tmp/worktree-batch-reproduction/logs/check-02-benchmark.excerpt.log) | excerpt derivative | 3857 | `a69079ed3a8e1302a1e77e419ca0d84d77fb24b1b038ed6463b67a87e76b63ea` |
| `tmp/worktree-batch-reproduction/logs/phase2-build-01.log` | [files/tmp/worktree-batch-reproduction/logs/phase2-build-01.excerpt.log](files/tmp/worktree-batch-reproduction/logs/phase2-build-01.excerpt.log) | excerpt derivative | 1296 | `ce86e34e4c08b6092292aa6794db82feeacbf113ac566c5c42d9fd2c6f0ee316` |
| `tmp/worktree-batch-reproduction/logs/phase2-build-02.log` | [files/tmp/worktree-batch-reproduction/logs/phase2-build-02.excerpt.log](files/tmp/worktree-batch-reproduction/logs/phase2-build-02.excerpt.log) | excerpt derivative | 2644 | `2cc51752f15d4ce56cd4eef5b6f795e7759d3ba86ab34e5553ac8ef0c747aab7` |
| `tmp/worktree-batch-reproduction/logs/phase2-check-01.log` | [files/tmp/worktree-batch-reproduction/logs/phase2-check-01.excerpt.log](files/tmp/worktree-batch-reproduction/logs/phase2-check-01.excerpt.log) | excerpt derivative | 6686 | `52680c64e6f35e7587eb53c5452b42534e734eda5f5b28a025fe1aada62106c9` |

## Excerpt provenance and omissions

Each excerpt identifies the complete source log's byte count/digest and the
retained 1-based inclusive ranges. All unlisted source lines are omitted.
These ranges refer to the checked original bytes, not mutable semantic IDs.
The complete logs are not archived. The excerpts preserve selected failures,
patch/configuration context, PASS summaries, observations, and conclusions;
they are not a claim that omitted output was independently reproduced later.

| Complete source log | Retained ranges | Complete source bytes | Complete source SHA-256 |
| --- | --- | ---: | --- |
| `tmp/worktree-batch-reproduction/logs/build-01.log` | 44-46, 521-523, 1049-1051 | 95798 | `5dff67a33d17e62d7d433af1e5cc3a85d8d91e33a43be0f3886393778510352d` |
| `tmp/worktree-batch-reproduction/logs/build-02.log` | 10-12, 14-18, 20-24, 2161-2165 | 144339 | `540fe2ed4e5c7976f71a2292290577087732083fa614dc1b71e8fbc802a75b57` |
| `tmp/worktree-batch-reproduction/logs/check-02-benchmark.log` | 4330-4334, 4342-4346, 4354-4386 | 288626 | `d6cce427b66728ad836890d70d915bb7624f907fb50b1936b0e88e319db36f78` |
| `tmp/worktree-batch-reproduction/logs/phase2-build-01.log` | 33-35, 37-39, 41-45, 68-70 | 4676 | `f26894a925347197693217009d69c77186135687af2155ef1289ab7e25cc3199` |
| `tmp/worktree-batch-reproduction/logs/phase2-build-02.log` | 28-30, 36-38, 45-47, 56-58, 2348-2352 | 154797 | `6ce0e4ec3ac01c7f7ea6831ab5b880f2061084b3d8dabf1b6b044c00c1771eb2` |
| `tmp/worktree-batch-reproduction/logs/phase2-check-01.log` | 16-41, 60-62, 70-72, 74-76, 2366-2370, 2379-2411 | 158645 | `37c82dce7cd5ebd60aaaaf75236e546d0cc3646dfb1ad5560bfa3b1a26e13f4f` |

## Fidelity verification and limits

Before capture, the source's original 31-entry inventory was checked against
current bytes. Both JSON result sets matched all console timing observations
to their six-decimal printed precision; all 20 medians recomputed correctly.
Phase-1 patch bytes matched ZIP members and phase-2 changes matched only the
two API adaptations. Selected source paths were regular UTF-8 files, below
1 MiB each, with no symlink escape or obvious credential/private-key content.

Every original copy was compared byte for byte, every excerpt against the
declared transformation, and every size/digest against the saved payload.
Source bytes were rechecked after capture, including the input ZIP. Only this
manifest and the declared 29 payloads belong to the snapshot. Capture itself
ran no build, test suite, formatter, experiment script, or network operation.
Checksums establish fidelity, not the truth of every statement or completeness
of selection.

The experiment does not establish SIGTERM/SIGKILL/power-loss behavior, strict
transaction atomicity, exclusion of ordinary Git/user writers, cross-platform
support, real-content checkout cost, or 10000-worktree scaling. The batch lock
coordinates cooperating batch invocations only. Do not equate fault-injection
rollback success with production readiness or a Git Roam application feature.

Nix may serve checks and benchmark outputs from cache; a later cache hit is
not a fresh timing run. Reproduction needs the pinned external Nix inputs and
may require downloads; this is not an offline Nix closure archive. Nix store
artifacts, full Git source copies/porting backups, the binary ZIP, unrelated
temporary files, complete compiler logs, and broader design history are excluded.
No post-capture rebuild is implied. Once checkpointed, retain this snapshot
unchanged; new evidence or corrected descriptions require a new snapshot.
