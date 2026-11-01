# Standard Git validation

## Actual evidence

On 2026-11-01, unpatched Git 2.56.0 from the application's locked nixpkgs passed
66/66 final fixture cases on x86_64-linux: 31 detailed SHA-1 scenarios on each of
files/reftable and four object/ref/Hook/worktree SHA-1/SHA-256 smoke cases.

Stable inputs/results are in the
[independent snapshot manifest](../archive/2026-11-01T05-50-42Z--native-git-validation/MANIFEST.md).
Five selected small text files total 62401 bytes: final flake, generated lock,
runner, derived result JSON, and authored report. Source-relative paths, roles,
byte counts and digests are in the manifest. They were screened and compared
before/after capture. Keep this snapshot immutable; the older patch experiment
archive remains separate. The temporary source is tmp/git-roam-v0.1.0-native-git/.

The ignored fixture inputs are not in project history. Their independent
reproduction/audit value warrants this bounded capture; prose memory and old
benchmarks do not preserve the assertions behind the observed native hazards.
The JSON was parsed from the builder's final RESULTS line and reserialized,
not copied as raw store output. Complete logs, scratch repos, closures, Git
sources and earlier source variants are excluded.

## Findings and application consequences

- Unique remote candidates create native tracking branches/worktrees; existing
  local tips are not advanced. Equal-OID multi-remotes still make guessing
  refuse, while explicit source selection succeeds. checkout.defaultRemote can
  select differing tips: apply product ambiguity rules before invoking Git.
- A mutually dependent new pair fails a single-branch fixture presence guard;
  joint conditional ref creation followed by upstream setup and worktree attach
  succeeds. Canonical remote, branch and upstream OIDs agree. This guard only
  demonstrates transaction coordination, not the product protocol validator.
- An occupied-path failure can leave a new branch; a post-checkout Hook returning
  23 leaves the branch, registered worktree and files. Inspect actual state after
  failure; compensate only unchanged safe state and preserve reference closure.
- Named hooks receive full transactions; rejection preserves both refs, and
  disabling only the guard retains the audit Hook. Zero old OID can describe an
  existing ref, which is still readable. Symbolic HEAD uses ref: values.
- Ordinary clean status and worktree remove can delete ignored user data.
  Add an ignored-data guard. Native removal refuses dirty/untracked/locked and
  main cases as tested. Detached records have no branch; moved paths are
  authoritative. Ignored nested linked worktrees work and remove deepest first.
  Native add follows symlink parents: product path boundaries need preflight.
- ff-only with no-autostash/no-overwrite-ignore preserves the tested unrelated
  unstaged and staged changes; overlap, untracked/ignored collisions and divergence
  refuse. Existing worktree or any dirty state is not itself an invalid update.
- Git ancestry can traverse a foreign Node without same-Node formal retention.
  Use the UUID-aware formal relation, not generic ancestry, for protection.
- A deterministic stale-read interleaving lets independent CAS advance A and
  delete needed B while B's object remains reachable. verify on an enumerated
  read ref prevents the tested stale delete. Same-ref CAS permits one writer;
  no arbitrary-writer global isolation is proved.

## Run history, limits, and next action

The initial build failed before Python: plain toString lost the script's Nix
store context. Path interpolation fixed it. A full run passed, then canonical
source/upstream assertions were strengthened and the final source was rebuilt,
again passing 66/66. The two runs' captured observations match. This is not a
benchmark or product implementation result.

Git 2.54, other platforms, full SHA-256 scenarios, crashes/power loss, production
Hook authorization, complete compensation and protocol validation remain untested.
The current standard Git 2.56 adapter has enough evidence to start project node 1.

Separately, the corrected root Git-source flake check passed on the clean committed
roadmap tree, reusing available results (zero checks needing execution), omitting
aarch64-linux/aarch64-darwin. Do not copy .git into treefmt source or disable live
protection. This project result is distinct from independent fixture results.

Next implement CLI/library/native Git foundation and tests. New untracked modules
need an explicit clean source snapshot or user staging for checks. The root check
and lock approvals were one-shot; isolated-check repetition covers this completed
experiment, not product builds. Obtain new applicable commands' authorization.
