# Post-v0.1.0 direction: local context Checkpoints

## Status and reason for the change

This records the agreed v0.2.0 protocol, whose phase-one pure implementation is
committed behind the temporary `GitRoam.Protocol.V2.*` namespace. It is not a
released interface, not a published release note and not permission to edit the
project README. The user chose to release the completed v0.1.0
knowledge-dependency DAG as a valuable first implementation, even though its
semantics are now being replaced. There are no known actual callers and no
workflow built upon v0.1.0. Therefore no existing deployment requires migration;
do not promise a general migration tool or forward compatibility to hypothetical
later users.

The v0.1.0 model formalizes complete, exact-version *knowledge dependencies* at
each Checkpoint. This provides a strong and elegant Git DAG but imports the
unverifiable semantics of knowledge dependence into a protocol that operates
beside Org-roam's dynamic, current-filesystem link resolution. Even automated
Org-link-to-HEAD declarations would encounter propagation pressure when target
versions advance, including cycles in link graphs that cannot simultaneously
be represented as mutually latest Git commit parents. Strict retention and
formal dependency-closure invariants made historical maintenance and deletion
nonlocal. More importantly, even creating A's Checkpoint could require first
creating Checkpoints on the referenced Nodes. The repeated difficulties were
primarily a mismatch of semantics and formalization, not just missing tools.

Preserve that implementation and its precise limits as v0.1.0. Treat the next
model as a deliberate change of interpretation, not a claim that the previous
implementation was invalid or that its original capabilities were worthless.

## Adopted protocol for v0.2.0

- A Node has a stable UUID identity, an independent persistent branch and an
  optional worktree. Its first-parent history records its own content evolution.
- Ordinary Content commits have one same-Node parent and need no static
  declaration of external knowledge dependencies.
- A Checkpoint locally fixes a caller-selected set of *external historical
  context* commits. It does not assert an exhaustive or semantically verified
  knowledge-dependency relation. Git-roam does not decide which context belongs
  to a document, nor interpret Org links.
- The adopted Git parent layout is `P(K) = [p, q1, ..., qn]` with `n >= 1`,
  where `p` is the same Node's immediate first-parent predecessor and each `qi`
  is an existing valid commit of a different Node. A referenced commit need not
  be a Checkpoint, nor the target Node's HEAD, nor a member of its current
  branch. The Checkpoint tree must equal `p`'s committed tree, so a Checkpoint
  never changes content while recording context and is not an equal merge.
- The protocol requires a Checkpoint's own tree to be disjoint from every
  context commit's tree; because each validated tree has exactly one top-level
  UUID directory, this is checked as a different Node identity. Pairwise
  disjointness among the context commits is *not* a protocol requirement: it is
  a recommended stricter convention, so several historical versions of the same
  external Node may all be contexts of one Checkpoint.
- A validated commit tree has exactly one top-level canonical-UUID directory.
  Inside it, `.roam` must exist as a regular or executable file whose content may
  change with ordinary Content. A Root contains only that marker. Node UUID and
  Root identity must agree, and one UUID keeps one Root across the validated
  graph.
- Validation reads only locally supplied commits and their Git ancestors; it
  does not query remotes or scan unreachable objects. Context commits need not
  remain reachable from their Node's current branch. Ordinary branch rewrites
  may drop old Content and Checkpoints, but a managed branch may not disappear
  or change its Root identity.
- The Checkpoint is an ordinary Git commit with additional parents. Because a
  Checkpoint always carries at least one context commit, there is no inherited
  dependency mapping, no empty-dependency declaration and no synthetic
  placeholder Content commit to manufacture. The `.roam` marker is still
  required in every commit tree.
- Creating A's Checkpoint may read and validate external objects but advances
  only A's ref. No other Node is required to establish a Checkpoint, and later
  changes to external branches do not force A to update its historical context.
  This is locality in space (no other Node write) and time (no propagation).
- Git parent reachability supplies the ordinary object-retention and transport
  consequences. Checkpoints have no special permanent-retention privilege:
  normal Git ref changes and reachability determine object lifetimes. Do not
  reintroduce the old formal-successor discard closure as a default rule.
- The caller chooses the selection policy. It may select a small deliberate
  set of commits, all relevant Org-link targets at their HEADs, or a dense
  context at every edit, but Git-roam core neither requires that policy nor
  continuously synchronizes it. Org-link relationships, including cycles,
  remain dynamic higher-layer semantics rather than Git DAG edges that must
  always mirror the current filesystem.

The new meaning does not remove the ability to associate precise historical
versions. For example, a paper Checkpoint can retain selected note commits,
without first modifying those note histories or promising that they are the
paper's logically complete dependencies. This use case motivated the value of
local context binding independently of whole-repository snapshots.

## Phase-one implementation and remaining work

Phase one, the isolated pure protocol, is committed as
`feat(protocol): introduce isolated v0.2.0 history model` behind the temporary
`GitRoam.Protocol.V2.*` namespace. `Protocol.V2.History` validates the adopted
commit kinds, tree and marker rules, context-tree disjointness, duplicate
parents, per-UUID Root consistency, object formats, cycles and unavailable or
wrong-type evidence; it exposes `firstParentHistory`, `contextParents` and
`reachableHistory`. `Protocol.V2.Repository` replaces the retained-Checkpoint
dependency closure with validated history plus managed refs, and validates
ordinary transitions that may rewrite history but not remove a managed branch or
change its Root. A separate `protocol-v2-tests` suite covers these rules on
SHA-1 and SHA-256. Phase one left the application layer on v0.1.0 and did not
make v0.2.0 usable through the CLI, Hook or worktrees. The subsequent
`refactor(discard): retire formal-history discard workflow` removed the old
specialized Discard command and its implementation; that is phase-two
preparation, not the protocol cutover.

Still to derive and implement in the application cutover:

- `checkpoint` construction and its CLI arguments, including how a caller
  selects context commits; the old `--depend`, `--drop-dependency` and
  `--clear-dependencies` interface is not assumed to survive.
- `check`, `status` and history/context presentation under the new model.
- Reference-transaction Hook validation without retained-Checkpoint or
  dependency-closure rules.
- Deployment, Node creation and deletion adapted to the new protocol.
- Application-level, end-to-end and documentation updates.

Completed phase-two preparation: the v0.1.0 `discard` command, its
`Application.Discard` and `Protocol.Discard` modules, the Discard-only worktree
helpers and the dedicated `discard-tests` suite are removed. That operation
existed only to withdraw a selected formal-successor closure required by the
v0.1.0 retention model; the adopted context model needs no such closure, so its
removal is deliberate architectural simplification, not a new rewrite API.
Read-only queries over reachability, first-parent history or context remain
compatible with this direction. The remaining commands still use v0.1.0
validation, so ordinary history rewriting is not yet unrestricted.

Temporary namespace cleanup is part of the cutover, not a separate release
task: when the v0.2.0 protocol becomes the production protocol, delete
`GitRoam.Protocol.V2.*` and replace `GitRoam.Protocol.History` and
`GitRoam.Protocol.Repository` with the new semantics, remove old
protocol-specific types, functions and modules, update every caller, the Cabal
registration, tests and docs, and keep no `V2` aliases or long-lived dual
protocol path. The cutover commit requires a complete build and test pass.

v0.1.0 and v0.2.0 DAG encodings need not be mutually interpretable. There is no
known existing-user migration obligation; do not claim a migration path until
one is designed and verified.

Deployment metadata in `.roam` (such as deployment-relative paths) is a later
extension candidate for v0.3.0 at the earliest, not part of this protocol work.

## Separate future capabilities and release boundary

The completed v0.1.0 implementation includes the serial 0-13 milestones, the
later explicit Node-identity and structured creation-output additions, the
PATH-resolved Hook, target-scoped shared deployment roots, and the scoped raw
Git object reader. Their accepted implementation and verification evidence
remain in [current.md](current.md), [implementation.md](implementation.md)
and the dedicated reader/performance records; this note does not upgrade those
checks to release verification.

The optional full-worktree-set deployment acceleration remains a particularly
important performance candidate: ordinary full deploy exists, but a native or
experimental *batch checkout acceleration* has not become a production feature.
Use the archived worktree experiment only within its stated limits; do not
claim its measurements establish production safety or speed. Alternative
human-readable deployment layouts/naming remain optional and unresolved.
Large-scale content changes across many independent Node branches could use
batch tooling to perform ordinary Git commits and coordinated ref updates,
with deployed worktrees and dirty indexes handled conservatively. None of these
features blocks v0.1.0 or is automatically required by the new Checkpoint
semantics. Do not start them as part of the protocol cutover.

Immediate sequence: implement the remaining application cutover to the v0.2.0
protocol, starting with the production history and managed-state validators;
Discard retirement is complete. Include the temporary-namespace cleanup. The
v0.1.0 README and release notes must continue to describe the implemented old
protocol, not this future one, until that cutover changes the documented
interface.
