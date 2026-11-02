# Persistent raw reader implementation

The user explicitly requested production integration of the measured optimization
after the independent experiment. Preserve the existing DAG, raw parent/tree
interpretation, replacement/graft/shallow boundaries, error distinctions and
ref/worktree rules. Scope is per-validation streaming plus existing per-call
caches; no daemon, permanent cache or unrelated optimization.

The production implementation and performance revalidation have passed.
Git.Batch owns a grouped
cat-file child, serialized request/response framing, bounded headers/stderr,
binary bodies, poisoned sessions after transport corruption, and controlled
shutdown/cancellation. Acquisition is masked; cleanup uses a separate worker so
owner cancellation cannot abandon it. TERM/KILL escalation is confined to the
owned process group. Cleanup/exit/trailing-output failures refuse success.

The native Git adapter has a private scoped-batch capability. observeGit and
withGitEnvironment preserve it, including production create/deploy observers.
The legacy bare Git constructor stays a transparent one-shot test double; it
never secretly bypasses its injected runner. withHistorySource shares a native
raw child and a per-call commit/tree cache. inspectState, validateCandidate and
the Hook local-history path use it. Blob batch metadata and generic raw tag/ref
resolution are unchanged. The generic nativeHistorySource remains a one-shot
provider used by test doubles and the session's scoped transport.

New Batch.hs tests use their own test executable as a fake child, without chmod,
shell scripts or live repository configuration. They cover binary/SHA variants,
concurrency, missing/wrong objects, malformed/short replies, stderr pressure,
exit/cleanup errors, cancellation with TERM ignored, child reaping and escaped
readers. A real files/reftable x SHA-1/SHA-256 matrix counts one raw child for
inspection/candidate validation. Existing WorktreeFixture now preserves the
native capability so existing real integration cases exercise streaming.

The user preauthorized repeated nix build/check/run/fmt as necessary in this
round. Continue single Nix job/core and bounded execution; no repeated permission
prompts for covered commands. The initial 240s snapshot build passed all 270
cases. Four more lifecycle/framing groups bring the final suite to 274 cases;
a test indentation error and a missing explicit throwTo import were corrected
in two failed compile attempts. The corrected build passed all 274 cases / 13
suites, with only the inherited Undeployment unused import warning. Root
formatting and snapshot flake checks passed (48 eligible files, zero changes).
Derivation: /nix/store/q9p6ksa2n6b979y0rlmp8ylpbyxm3gvg-git-roam-0.1.0.drv.
A 50-file source
snapshot is made by tmp/prepare-reader-session-source.py, excluding Git metadata.
No project staging/commit or real protection installation. The new CHANGELOG
Changed item is checked after correctness and performance passed; TODO 0.1.0
remains unchanged. Final formatting, snapshot build and flake check passed;
the package reused the same 274-case verified derivation, and the final treefmt
check processed 48 eligible files with zero changes. All 50 current source
files match the final snapshot. Final manifest SHA-256:
2700a8e47f4c6f8a69137b28c8985f14feb590bee72aaef465f44e5c7282113b.

Production performance revalidation completed under
tmp/object-reader-production-performance/. It uses the archived deterministic
fixture recipe and locked toolchain, but measures actual native production
sessions (observeGit, no experimental stream parser) versus an explicit one-shot
control in the same current validator and caches. It is not a separate rebuild
of the unchanged old project commit. Each of four cases has three paired serial
repetitions, one capability, a 1 GiB managed heap cap, and 180s child deadlines.
All 24 runs exited zero, without retry. Every case's six result digests match;
all four generated import stream hashes match the original fixture recipe.

| Nodes / Checkpoints per Node / fanout | Median seconds, one-shot / production | Git launches | Median max RSS MiB |
| --- | --- | --- | --- |
| 100 / 1 / 0 | 1.0365 / 0.0437 | 611 / 11 | 14.5 / 13.1 |
| 1,000 / 1 / 0 | 10.8681 / 0.3159 | 6,011 / 11 | 42.6 / 30.6 |
| 10,000 / 1 / 0 | 109.6696 / 2.7429 | 60,011 / 11 | 345.7 / 243.6 |
| 100 / 10 / 2 | 7.2242 / 0.1409 | 4,211 / 11 | 31.7 / 22.4 |

Production starts exactly one raw batch child in all runs, plus one metadata
and nine repository queries. The formal implementation's 10,000-Node speedup
is about 40x; do not reuse the prototype's 70.3x as its production result.
10,000-Node production times: 2.6880, 3.0888, 2.7429 seconds; control:
109.6696, 108.3003, 109.7124. RSS is GNU time maximum, not simultaneous process
RSS summed; managed heap is not physical RSS. OS caches were not flushed;
small packed SHA-1/files fixtures and inspection core only, no CLI rendering.
No other platform or minimum-Git-2.54 verification is implied.

Run: tmp/object-reader-production-performance/runs/all-1G-20261101T192842.427029Z/.
REPORT.md contains the derived table and controls. flake/SOURCE.json inventories
the actual 50 measured uncommitted source files, based on the user-committed
standard-Git implementation. Measured manifest SHA-256:
9e4d8dfdc7c16261a8b473fc6bd865d5d012865fe882eff17a2cebb80618d3c5.
The measurement source remains fixed when final documentation changes. These
are local temporary evidence paths, not guaranteed long-term dependencies.
The original immutable archive already retains the fixture recipe and toolchain;
this ordinary implementation retest does not establish a new independent
archival need. Durable results, controls and limits are distilled here. Do not
archive generated fixture repos, packs, build outputs or the whole tmp directory.

The whole intended project diff was reviewed, including the two added files;
diff --check passed. This is one cohesive optimization with its lifecycle tests
and documentation. No protocol module, lockfile, live protection config or
pre-existing Node worktree/index was modified by the task. A pre-existing
Undeployment test import warning remains unchanged.

The user has committed the production implementation with the reviewed
`perf(git-roam): reuse a persistent raw object reader per validation` message.
Read-only comparison of every committed blob confirms all 50 files match the
final verified manifest, with no additional tracked files. The project worktree
is clean. The committed source snapshot supplies an exact project-parent
provenance for the final implementation verification, rather than a guessed
association. Measurement source predates only the final documentation checkbox;
the performance manifest above continues to identify that measured copy exactly.
No build or performance rerun was necessary merely to confirm the commit.

Next: await the next user task. The optimization, correctness checks, production
performance measurements and documentation are complete. Keep the minimum-Git,
other-platform and benchmark workload limits explicit. Do not start unrelated
worktree optimizations, release changes or archival expansion automatically.

## Committed-source performance retest

The user separately requested a new isolated flake performance retest after
committing the optimization. This is tmp/committed-reader-performance/, not a
reprint of the prior uncommitted results. prepare.py restores all 50 small blobs
from the exact committed production tree, with git-blob/SHA-256 provenance in
flake/SOURCE.json. All copied hashes were rechecked after measurement. Source
manifest SHA-256: e72a934e020d577533d41bddcaf94d376249eac22584ab5bb03ae5c477edc399.

The archived run.py is copied byte-exactly as fixture_recipe.py and imported
only for its unmodified deterministic fixture() function. The archived lock is
also byte-exact. Both generated streams and all six production validation
results match the archive's 1,000/10,000-Node hashes/digests. The fixtures have
one Root, one Content and one Checkpoint per Node, no external dependencies,
packed SHA-1/files. Large generated repositories were omitted from the original
archive; reproducing their exact generator streams is the dataset identity.

Only native production observeGit/inspectState is measured, with no prototype
or one-shot mode executed. Three invocations per case, serial -N1 -M1G, one
packing thread, 60s child deadlines. Build/check/run commands had 120s outer
deadlines and NIX_CONFIG single job/core. All commands and six measurements
passed; no timeout, failure, retry, heap exhaustion or budget increase occurred.
The isolated flake check warned only about an optional missing app meta field.

| Nodes | Three validation times, seconds | Median seconds | Median max RSS MiB |
| --- | --- | --- | --- |
| 1,000 | 0.190306686, 0.217523995, 0.160588873 | 0.190306686 | 30.10546875 |
| 10,000 | 2.455160513, 3.054985528, 2.241433720 | 2.455160513 | 243.53515625 |

Every run starts exactly one raw child, one metadata process and nine other
repository queries (11 total). This confirms the per-validation session on the
actual committed implementation. Git 2.56.0/GHC 9.12, x86_64-linux. OS caches
were not flushed; inspection core excludes CLI rendering. GNU time max RSS is
not summed simultaneous RSS and the managed heap cap is not a total RSS cap.
Do not assert cold-storage, other-platform, or minimum-Git compatibility, or
interpret run-to-run differences as a separately measured code improvement.

Raw observations: tmp/committed-reader-performance/runs/20261102T005250.860888Z/.
REPORT.md and README.md at the experiment root explain reproduction/controls.
Those are ignored local evidence paths, not durable external dependencies;
results and required method are distilled here, with the original archived
recipe and the exact production project-parent providing recoverable inputs.
No archive expansion is necessary for this retest; do not copy generated large
fixture data into GAW by default. Project working tree/index/refs/lock and the
original archive remained unchanged, and the worktree is clean.

The explicitly requested retest is complete. Report its production-only results
and limitations; await the user's next task. No duplicate full test-suite run
or product edit was needed for this isolated performance measurement.
