# One-off Phase B performance experiments

This is development evidence, not a product benchmark facility or an instruction
to add one. The user explicitly requires all experiment code and generated
repositories to stay in temporary directories (or selected GAW archive material).
Do not add a benchmark stanza, executable, script, dependency or package to the
formal source tree. No wall-clock threshold belongs in the default tests.

The accompanying Observation.hs and run.py are the temporary experiment tools.
RESULTS.org contains derived measurements, originally drafted for an abandoned
formal benchmark directory. Any references there to cabal/bench are historical;
read this note and current GAW memory instead. The old draft README.org is not
retained as reproduction guidance. The sample archive records original data.

## Reproduce in an isolated source copy

1. Use the actual source revision of interest. B6 is
   0376d2691cf1bf4abad00a476b41cb5bc4d9aa9a. The measured B7 production changes
   were upstream config-problem indexing and missing-object list accumulation.
   Use current memory's verified source manifest/actual later commit for B7;
   do not pretend an uncommitted source state has its own project commit.
2. Copy only the intended project sources into a fresh temporary source directory,
   including its locked flake and package files. Do not alter the real worktree.
3. In that TEMPORARY COPY ONLY, place Observation.hs at
   cabal/experiment/Observation.hs and append temporary-stanza.cabal to the copied
   cabal/git-roam.cabal. All dependencies already exist in the project. This is
   an experimental build input, never a formal-source or release change.
4. Build the temporary flake using the ordinary package with overrideAttrs:
   add --enable-benchmarks to configureFlags and install the resulting
   dist/build/observation-benchmark/observation-benchmark in the temporary
   derivation's bin directory. Use --no-link, --no-update-lock-file, one job/core
   and a 300-second outer timeout, as in the executed B7 experiments.
5. Run the saved Python driver with the resulting temporary binary, a fresh
   directory and the intended Git executable. For example:

   python3 run.py --runner /nix/store/EXPERIMENT/bin/observation-benchmark \
     --git /nix/store/CHOSEN-GIT/bin/git --baseline ACTUAL_SOURCE_DESCRIPTION \
     --directory /absolute/temporary/experiment --sizes 10 100 1000 10000 \
     --backends files reftable --repetitions 3

   Add --object-format sha256 for the second object format. Use --shape shared
   for shared Content/context histories and --shape config-errors --workloads
   remote default for the indexed-diagnostics comparison. A fresh directory is
   mandatory. Fixture generation is timed separately. Each command/query has
   a 120-second timeout; the full experiment may use an outer 300-second limit.

The Haskell proxy counts actual native Git launches separately from OID requests
inside the shared raw batch process. It does not replace production transport;
it forwards requests to native Git and adds measurement overhead. Logical
observeGit events include session startup but not internally routed requests.
Output byte counts force complete JSON encoding without writing large reports.
Encoding includes lazy report construction; observation/encoding timing is an
operational split, not a perfect separation of all pure work.

## Actual evidence and limitations

The retained primary runs comprise 212 workloads / 636 samples, serial execution
without concurrent Nix builds and warm OS caches after fixture generation. Root
fixtures cover all four format/backend combinations at all four scales. Shared
quiet fixtures use SHA-1 and 10,000 Nodes on both backends; configuration-error
before/after runs use SHA-1 and all four scales. Peak RSS and cold cache were not
measured. Earlier exploratory runs that overlapped compilation are excluded from
primary timing tables. No absolute latency guarantee is inferred.

Functional package tests bind Git 2.56.0 at
/nix/store/xgw813vgzl2q0696sq45adpj0xd690jq-git-2.56.0/bin/git.
Agent commands and performance runs used the session's mapped Git-with-svn 2.56.0:
/nix/store/2qpb7835xdl1aayzr7q24kbrs2d1ajv3-git-with-svn-2.56.0/bin/git.
Before and after timings use that same latter executable. Do not conflate the
store paths or compare different Git variants as if measuring only B7 changes.
CPU: Intel Core Ultra X7 358H, x86_64-linux. Minimum Git 2.54 and other platforms
were not tested. Fixture repositories and binaries are intentionally not archived.

The final driver has small robustness/metadata refinements after the original
runs (fresh-directory refusal, completeness checks and runner-path metadata).
Do not claim its bytes are the exact driver version for every historical sample;
fixture generation, native counting and repeated-query methodology are unchanged.

Retained scripts are optional historical development material. The formal
regression suites are the ongoing cost/safety guarantees; future agents should
not rebuild a product performance framework from this archive.
