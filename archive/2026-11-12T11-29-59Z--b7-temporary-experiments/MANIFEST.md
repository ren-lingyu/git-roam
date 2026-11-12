# Temporary Phase B experiment material

Historical development evidence; not a product capability, active Skill or instruction to change formal source.

Captured 2026-11-12T11-29-59Z. Source root: /home/lingyu/Projects/git-roam.
The user explicitly rejected formal benchmark infrastructure. All accompanying
experiment files have been moved out of the formal source tree to tmp/.
Cabal benchmark wiring, formal benchmark dependencies/entries and ignore exceptions
are removed. README/CHANGELOG contain no raw experiment data or machine timings.

Retain only the counter/fixture source, measured summary and necessary temporary
reproduction instructions: individual samples alone cannot explain how native
processes were distinguished from requests or reproduce the valid shared closure.
No old product-oriented draft README, fixture repositories, binaries, environment
dumps, test logs or full conversations are selected.

This is a fresh snapshot; the earlier sample archive is unchanged:
../2026-11-12T11-16-04Z--b7-performance/MANIFEST.md.
That archive contains exact original sample bytes; references there to draft
cabal/bench paths are historical and superseded by this scope correction.

| Source relative to project root | Archived path | Role | Bytes | SHA-256 |
|---|---|---|---:|---|
| tmp/b7-performance-tools/Observation.hs | files/tmp/b7-performance-tools/Observation.hs | Temporary native process/request counter | 4969 | 23ff35d313723037fe8713f8b141873269ed0ec4f82466d395231ce9de6fc04a |
| tmp/b7-performance-tools/run.py | files/tmp/b7-performance-tools/run.py | Temporary fixture/query driver | 8891 | 99a269c801f7bea7581995745332af87fa113b3af90f9d3a2abbaf388aaf41f7 |
| tmp/b7-performance-tools/RESULTS.org | files/tmp/b7-performance-tools/RESULTS.org | Derived results, retained only as GAW evidence | 11560 | dfe63787dee2e0cb565a9536d9e451f85a0adcf2c37c47304897ebdbb0938c86 |
| tmp/b7-performance-tools/REPRODUCE.md | files/tmp/b7-performance-tools/REPRODUCE.md | Current reproduction and scope limitations | 5117 | e6645477540db95312a01e79b1df7e3312fda7cb46f59dcd0dcc7443f711bef6 |
| tmp/b7-performance-tools/temporary-stanza.cabal | files/tmp/b7-performance-tools/temporary-stanza.cabal | Stanza for an isolated TEMPORARY copy only | 303 | 6a31361806dee1a1eb90386ebab7d914ec36a905b2dce3d036f5b54c48e859af |

B6 actual baseline is 0376d2691cf1bf4abad00a476b41cb5bc4d9aa9a.
After measurements used then-uncommitted B7 production code. Capture HEAD is
not presented as an exact commit for that uncommitted result. Final test/build
evidence is maintained separately in current memory.
The Haskell counter is the measured implementation. The driver has small
post-run robustness/metadata refinements; do not claim byte identity for all
historical driver versions. REPRODUCE.md describes that limit and the distinction
between package-native Git 2.56.0 and the command-mapped Git-with-svn 2.56.0.

RESULTS.org was drafted before the user correction. Its cabal/bench links and
benchmark packaging wording are historical, not recommendations for formal
source. REPRODUCE.md and current memory define the accepted temporary-only use.
Timing evidence is warm-cache and includes proxy overhead, three samples per
workload, no concurrent Nix build in retained primary runs. No cold-cache/RSS,
minimum Git 2.54 runtime, other-platform or large Deploy/Undeploy claims.

Existing structural tests, strict validation and safety boundaries are the
maintained guarantees. Retaining these scripts does not establish a permanent
performance framework or require future agents to re-run every experiment.
