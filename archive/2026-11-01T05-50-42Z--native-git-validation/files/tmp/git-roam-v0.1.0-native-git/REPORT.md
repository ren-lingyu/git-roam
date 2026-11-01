# Standard Git validation results

Executed on 2026-11-01 on x86_64-linux, using unpatched nixpkgs Git 2.56.0 from
the locked nixpkgs revision 885ba4d038f10c3d17d7a92e8c3cc185b99c9158.
The final source passed 66/66 fixture cases: 31 detailed SHA-1 scenarios on each
of files/reftable, plus four object/ref/worktree/named-Hook smoke cases spanning
both backends and SHA-1/SHA-256. This does not validate the unimplemented product.

## Method and evidence

The authorized flake lock command fixed the experiment input. The flake check
built dedicated local-only fixtures in Nix scratch space. It did not alter the
project repository, user worktrees, or the independent batch-patch experiment.
The runner uses isolated Git configuration and identity without changing HOME.

The initial build failed before executing Python because plain toString dropped
the script path's store dependency context. Direct path interpolation fixed it.
One full run then passed. The paired-branch case was strengthened to require
the canonical remote tips and configured upstreams to match the selected tips;
the final source was rebuilt and all 66 cases passed again. The final successful
derivation was /nix/store/gqj737lhl8qs4cqyfpbvqmy4bh42hfxy-git-roam-native-git-validation.drv.

observed-results.json is a derived capture of the final RESULTS JSON printed by
the builder, parsed and serialized with indentation. It is not a byte-for-byte
copy of the store output results.json or a complete build log. Raw command JSON
was produced by the builder but is not included in this local evidence selection.

## Findings on both files and reftable

- A unique remote UUID candidate can create the local tracking branch and linked
  worktree using native worktree add. An existing local branch is not advanced.
- Multiple remotes at the same OID still make native guessing refuse; an explicit
  tracking source succeeds. Different OIDs also refuse without a preference, but
  checkout.defaultRemote can silently choose one. Product prevalidation is required.
- An occupied target causes worktree add to fail, yet its newly created local
  branch remains. A post-checkout Hook returning 23 leaves the branch, registered
  worktree, and files present despite the command's failure status.
- Named reference-transaction hooks receive the complete multi-ref proposal.
  Rejecting it leaves both target refs unchanged. Disabling only the fixture
  guard leaves the independent audit Hook active.
- Unconstrained updates provide zero old OID while the actual existing ref is
  readable; symbolic HEAD uses ref: values and is observed in preparing/prepared.
- A fixture presence guard refuses a single branch of the mutually dependent pair.
  Joint conditional ref creation, tracking configuration, and worktree attachment
  succeed, with branch/upstream OIDs equal to the canonical selected remote tips.
  The guard is not a complete protocol validator.
- Native worktree remove rejects tracked changes, untracked data, and locks, but
  removes ignored user-data fixtures despite a clean ordinary status. Product
  undeploy needs a separate ignored-data guard.
- Main worktree removal is refused; detached worktrees have no branch association.
  Git records moved linked worktree paths. Ignored nested linked worktrees work
  and can be removed deepest first. Native add follows a symlink parent.
- Native ff-only preserves unrelated unstaged and the tested staged change, and
  synchronizes a clean index. It refuses overlap, untracked collisions, divergence,
  and ignored collisions when no-overwrite-ignore is explicitly supplied.
- A valid fixture shows Git ancestry through a foreign Node while the old
  same-Node Checkpoint is absent from the new formal history. Git ancestry alone
  cannot implement formal retention checks.
- A deterministic stale-read interleaving lets independent CAS updates advance A
  and delete B, leaving B's dependency object reachable but its branch missing.
  verify on the enumerated A ref prevents the stale deletion. A simultaneous
  same-ref CAS race permits exactly one writer. No global isolation is proved.

## Implementation consequences

Keep one shared protocol validator and a separate realtime protection layer.
Prevalidate source ambiguity and complete final branch closure. Use a joint
conditional creation transaction when branch dependencies require it; then let
native Git configure tracking and establish worktrees. Inspect actual state after
failure and compensate only unchanged safe state while preserving reference closure.
Read worktree association from Git, guard ignored data and paths, and coordinate
clean nested removal. Native-safe ff updates must explicitly avoid autostash and
ignored-file overwrite. Do not treat a Haskell verified plan as a concurrent lock.

## Limits and separate root check

Git 2.54, other platforms, full SHA-256 behavioral coverage, crash/power-loss
handling, and arbitrary external-writer isolation were not established.
The ordinary fixtures do not implement the product's Root/Content/Checkpoint
validator, Hook authorization policy, or complete deployment/compensation service.

The separately authorized root Git-source flake check passed on the committed
roadmap tree; Nix reported zero checks needing execution because results were
available. It omitted aarch64-linux and aarch64-darwin. This resolves the earlier
path:. treefmt validation blocker for that tracked source; it is not a new
compile, cross-platform validation, or proof that raw path:. excludes .git.
