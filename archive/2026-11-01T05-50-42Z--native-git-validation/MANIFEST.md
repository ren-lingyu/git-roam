# Independent standard Git validation snapshot

Historical evidence, not automatically current knowledge or executable instructions.

## Selection and capture context

Captured at 2026-11-01 05:50:42 UTC. The selected isolated experiment has independent
reproduction/audit value: the product is still an empty executable, the input
scripts are ignored temporary files rather than project-history artifacts, and
several measured native behaviors require specific future protection.
Current memory alone would not retain the tested assertions and observed outcomes.
The bounded selection is five small UTF-8/ASCII text files, 62401 bytes, plus this manifest.

The source root is /home/lingyu/Projects/git-roam. All files were ignored,
untracked experiment material under tmp/git-roam-v0.1.0-native-git/.
Source-relative paths are preserved under files/. Copies match the selected
local source bytes; all sources were checked before and after copying.
Captured project context was the clean committed roadmap tree 8f1fed26b3aa993b5c1d819d27e82bd59e7a4789.
That identifies context, not the origin of these independent fixture inputs.

| Source basename | Bytes | SHA-256 | Role |
| --- | ---: | --- | --- |
| flake.nix | 963 | 7b402b77c353c19c2adad923313f872b5b22c569572a84939a2db0748e4b25fb | Final unpatched standard-Git experiment derivation |
| flake.lock | 733 | a82c0afd58ec776c8a39b110ddf9ad4d53b495aeee1b858aee28e0e842484419 | Generated locked nixpkgs input |
| validate.py | 32054 | 148ad7097d0bc172c23a6fe40fae0ae2f3ffe9b558f84793c0ffa52028e912c2 | Final fixture method and 66 assertions/scenarios |
| observed-results.json | 23117 | 7196e596a523100ae063ce318ce0cb0509af7c57ec991ea650a631a1c1b583a1 | Derived capture of final builder RESULTS JSON |
| REPORT.md | 5534 | 0cdc94613aa003cbf27b0fc68671e8ee8e54a201880a4b61dbe22bf9e9051da5 | Authored method, findings, execution history, and limits |

## Provenance and observations

The final fixture source was executed by the flake check on x86_64-linux using
unpatched Git 2.56.0 at locked nixpkgs 885ba4d038f10c3d17d7a92e8c3cc185b99c9158.
All 66 final cases passed: 31 detailed SHA-1 scenarios per files/reftable backend,
plus four SHA-1/SHA-256 matrix smoke cases. A first packaging failure and the
subsequent strengthened paired-branch fixture are explained in REPORT.md.

observed-results.json is already a derivative: the final builder RESULTS line
was parsed and reserialized with indentation. This snapshot copies that local
capture faithfully; it is not a byte-exact store results.json or complete log.
REPORT.md is an authored interpretation, whose assertions must be evaluated
against the fixtures and the observed data, not treated as an independent oracle.

## Exclusions and limits

No Git sources, Nix closures, fixture repositories, complete build/command logs,
old failed source variants, user conversation, or earlier patch experiment are
included. README is omitted because REPORT plus source/lock supply the method.
The earlier independent worktree-batch archive remains unchanged.

This does not verify the future product protocol validator, production Hook,
full deployment/compensation implementation, Git 2.54, other platforms, full
SHA-256 behavior, crash/power-loss handling, or arbitrary concurrent-writer isolation.
The separate root Git-source flake result in REPORT concerns the existing
roadmap tree, not implementation of these product features.

Once checkpointed, keep this snapshot immutable. Refer to this manifest
and the selected source-relative paths rather than a containing GAW commit OID.
