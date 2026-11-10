# Stage C isolated verification

## Completed user task and source boundary

The user requested isolated reproduction of the full check and C coverage audit,
plus archival assessment. Both requested checks are now complete. No production
patch, release-state transition, performance experiment or project Git write
was part of this task.

Workspace: tmp/v020-stage-c-verification/. prepare.py reconstructs 52 index blobs
after asserting main d8503afd02ae02ab38c604888c0c84e1e2a3cbdb and exactly three
staged document paths. Production source, tests and Cabal manifest are from that
committed code baseline. The README/CHANGELOG overlay is uncommitted and is not
represented as part of a project commit or a published release.

| Staged documentation | Exact inspected blob |
| --- | --- |
| CHANGELOG.org | 6f8b3fd10e8e490e95cf8af1ec84a31dfb1b9cdb |
| CHANGELOGS/v0.2.0.org | 523fd5b0010a73148dcc71c8671c57d24ca812a4 |
| README.org | 6d4aca3c50566e63358a9cedcf40eb6ae8ebad1d |

SOURCE.json records every file's blob/SHA-256, its origin and the fresh-flake
hash. Source manifest SHA-256: 21252c6867b684f9f791cb5bf2b4c5aef72b96ea211e9602f75f56a4ff05bf82.
Both copies were verified against those hashes before the successful rerun;
original files and the timed-out log were retained unchanged.

source/ is byte-exact. fresh/ changes only flake checks to add an override with
preCheck/postCheck markers, preserving the actual package, Cabal declarations,
-Wall -Werror, compiler and dependencies. This forces a fresh check derivation
without duplicating suites in Nix or modifying production/test code. The source
association identifies the exercised committed code baseline, not the extra
instrumentation or uncommitted document overlay.

## Independently observed results

Original source flake check passed. Product derivation
/nix/store/0fy22w72k9vpajxixnw8yfiqzlk42qhv-git-roam-0.1.0.drv was cached, while
the document treefmt check freshly processed 50 eligible files with zero changes.
The source snapshot excludes Git metadata and includes the newly staged notes.

Fresh actual compilation and execution then passed all 14 suites / 250 cases,
with both fresh BEGIN/COMPLETE markers and Nix exit 0. Later invocations may
reuse this completed derivation; actual execution is established by the observed
compile/check log, not merely by invoking a target named fresh. This is independent
execution, not merely the earlier handoff's successful user report. Derivation:
/nix/store/kd0dim1a51y6vyds16m7hcq1xvrk7ldf-git-roam-0.1.0.drv.

| Suite | Passing cases |
| --- | ---: |
| unit-tests | 13 |
| protocol-tests | 28 |
| output-tests | 3 |
| deployment-tests | 17 |
| protection-tests | 8 |
| batch-tests | 30 |
| undeployment-tests | 17 |
| inspection-tests | 33 |
| checkpoint-tests | 20 |
| end-to-end-tests | 4 |
| creation-tests | 24 |
| deletion-tests | 26 |
| worktree-tests | 18 |
| git-adapter-tests | 9 |
| Total | 250 |

The first forced build reached its 120s deadline after compilation and
9 suites / 169 passing cases, while end-to-end was running (exit 124); no case
failure was observed. No automatic retry occurred. The user explicitly
approved one 300s rerun of the same target. After source-hash verification,
that run finished successfully. Both logs remain separate. Commands used
NIX_CONFIG max-jobs=1/cores=1. Compiler: GHC 9.12.3; the locked x86_64-linux
standard-Git build. Other systems were omitted. No exact minimum-Git or
all-platform claim follows. Package version remains 0.1.0; it is not changed
by protocol verification.

## Coverage and archival assessment

[stage-c-coverage.md](stage-c-coverage.md) retains the derived requirement-to-test
mapping; 91 function locators were resolved against actual source declarations.
All adopted C semantic groups have maintained cases; this audit found no missing
required semantic group that justifies duplicate tests or a product patch.
Pure, native, application, deterministic injected-race and real CLI/Hook coverage
are separate evidence layers. Negative edge cases and PTY confirmation are
predominantly files/SHA-1, not every backend/format cross-product. Arbitrary
external writer stress and literal execution of every README step remain outside
this evidence. Passing suites do not establish broader guarantees.

Explicit user request triggered archival assessment. Final decision: no new raw
archive snapshot. Source/tests are recoverable from project history; format
checks and two phase markers are ordinary verification, not a new independent
Git-behavior or performance experiment. The timeout is an explicit resource
budget, not a demonstrated product failure. Distilled results, source boundaries
and this coverage matrix suffice in maintainable memory. Do not archive temporary
repositories, binaries/caches, complete compiler logs or duplicate project trees.
Existing experiment archives are untouched. The local REPORT.md, COVERAGE.md,
RESULTS.json, source copies and logs remain under the ignored experiment directory;
none is a required durable dependency for the conclusions above.

## Next action

The requested isolated reproduction and assessment are complete. Do not rerun
unchanged tests merely to repeat a successful check. Resume remaining C document,
version and release preparation only under its applicable user instruction.
This result does not itself change release states, create tags, publish, stage
or commit the project. Preserve the existing three staged documents and continue
to distinguish current code, uncommitted manuscripts and actual release facts.
