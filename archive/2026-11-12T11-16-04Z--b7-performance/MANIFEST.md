# Phase B benchmark samples and conditions

Historical measurement evidence, not current instructions or a release/compatibility guarantee.

Captured 2026-11-12T11-16-04Z from the project worktree rooted at /home/lingyu/Projects/git-roam.
Selection: five completed serial measurement runs, 212 workloads / 636 samples.
Retain individual samples and instrumentation/fixture metadata so later reviewers can
recompute medians, assess timing variation and audit process/request-count claims.
Distilled conclusions alone would lose these independent measurement observations.
No build logs, conversations, fixture repositories, binaries or overlapping exploratory runs are included.

Capture HEAD is B6 0376d2691cf1bf4abad00a476b41cb5bc4d9aa9a, with uncommitted B7 changes.
Before measurements use B6 production code plus the same opt-in Haskell harness;
after measurements use the two B7 bounded production optimizations, not a committed B7 tree.
The data baseline labels describe that provenance; HEAD is not claimed as the after-source.
Both comparison binaries passed their then-current full default suites; the last
native lazy-fetch regression was added later and is outside these benchmark builds.

All files are ignored/untracked generated UTF-8 JSON Lines in tmp/. They contain
deterministic fixture identities and local store/workspace paths, not user knowledge data.
No credentials or raw environment dumps were selected. Bytes are copied without normalization.

| Source (relative to project root) | Archived path | Workloads | Bytes | SHA-256 |
|---|---|---:|---:|---|
| tmp/b7-roots-quiet/results.jsonl | files/tmp/b7-roots-quiet/results.jsonl | 80 | 171288 | b0d19fe0a2edb5868e1bf87604bffe2ade3a1f5066e39c338b06a8201f7cc55f |
| tmp/b7-roots-sha256/results.jsonl | files/tmp/b7-roots-sha256/results.jsonl | 80 | 171474 | a364d6c8d98fe927ae2e775c1ee5832b1b7158f0a5f6476aeb797160b414f610 |
| tmp/b7-shared-quiet/results.jsonl | files/tmp/b7-shared-quiet/results.jsonl | 20 | 43093 | 43008242d878fea34ea7cd81a9520b86b65101114f479263975890f8d5a0bb60 |
| tmp/b7-config-before/results.jsonl | files/tmp/b7-config-before/results.jsonl | 16 | 34014 | c1987512f8c1b724e85ed63a3483ed17eab99952b3bdef542a1e2755057733ef |
| tmp/b7-config-after_/results.jsonl | files/tmp/b7-config-after_/results.jsonl | 16 | 34572 | ac936a5043d2b9b98e722f2f606f8cd10034505ca9a0307cc54f90711103c732 |

Run conditions: x86_64-linux, Intel Core Ultra X7 358H, pinned Git 2.56.0.
Root fixtures cover SHA-1/SHA-256 x files/reftable at 10/100/1,000/10,000 Nodes.
Shared quiet fixtures cover SHA-1 x both backends at 10,000 Nodes with 29,999
reachable commits; config before/after covers SHA-1 x both backends at all four scales.
Each workload has three samples, warm OS caches after native fixture generation,
fresh application evidence, no concurrent Nix build during these selected runs.
Process proxy/logging overhead is included. The proxy counts native Git launches;
raw request records are counted independently within the scoped batch session.
Logical adapter observations are not interpreted as raw session request counts.
Selected config runs intentionally yield incomplete reports and N+1 diagnostics.

Some early driver versions record a runner hash rather than its store path or
leave processor blank; the binary paths and CPU provenance are stated in
cabal/bench/RESULTS.org and current project memory. These metadata differences
do not change the identical native proxy/measurement method or fixture protocol.
Peak RSS, cold caches, minimum Git 2.54 runtime and other platforms are untested.
No raw data proves exhaustive malformed-ref detection, atomic snapshots or release readiness.

Reproduction and derived tables live in cabal/bench/README.org and RESULTS.org.
The normal fixture has one shared marker blob: it does not measure large missing-blob latency.
Large Deploy/Undeploy planning remains Stage A work.
