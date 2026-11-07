# Post-v0.1.0 direction: local context Checkpoints

## Status and reason for the change

This is durable GAW planning memory, not an implemented protocol, a published
release note or permission to edit the project README. The user chose to
freeze and release the completed v0.1.0 knowledge-dependency DAG as a valuable
first implementation, even though its semantics will be reconsidered for
v0.2.0. There are no known actual callers and no workflow built upon v0.1.0.
Therefore no existing deployment requires migration; do not promise a general
migration tool or forward compatibility to hypothetical later users.

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

## Agreed semantic direction for v0.2.0

- A Node has a stable UUID identity, an independent persistent branch and an
  optional worktree. Its first-parent history records its own content evolution.
- Ordinary Content commits have one same-Node parent and need no static
  declaration of external knowledge dependencies.
- A Checkpoint locally fixes a caller-selected set of *external historical
  context* commits. It does not assert an exhaustive or semantically verified
  knowledge-dependency relation. Git-roam does not decide which context belongs
  to a document, nor interpret Org links.
- The candidate Git parent layout is `[p, q1, ..., qn]` with `n >= 1`, where
  `p` is the same Node's immediate first-parent predecessor and each `qi` is an
  existing valid commit of a different Node. A referenced commit need not be a
  Checkpoint, nor the target Node's HEAD, nor a member of its current branch.
  The initial conservative design keeps the Checkpoint tree equal to `p`'s
  committed tree; allowing simultaneous content changes is a separate choice,
  not a fundamental semantic requirement.
- The Checkpoint is an ordinary Git commit with additional parents. A context
  must contain at least one external commit to warrant that structure; there
  is no inherited dependency mapping or explicit empty-dependency declaration,
  and no need for a Root marker or placeholder Content commit.
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

## Protocol and interface work still to derive

- Re-derive valid Root/Content/Checkpoint histories from the new first-parent
  and additional-parent roles; specify identity checks for historical commits
  even when they are no longer reachable from their original Node branch.
  The first-parent Root identifies an individual commit independently of the
  current branch tip. Do not silently carry forward the old formal-history
  projection or global retained-Checkpoint dependency-closure validator.
- Determine the ordinary Git ref-update and worktree-safety boundaries. The
  ability to rewrite or abandon a Checkpoint follows Git's normal reachability
  rules; user-facing destructive operations may still use confirmations for
  user-data safety, but no special Checkpoint retention is assumed.
- Revisit `checkpoint`, `check`, `status`, `discard`, Node deletion, Hook and
  tests against the new semantics rather than preserving obsolete options or
  validation code for compatibility. Do not assume the old `--depend`,
  `--drop-dependency` and `--clear-dependencies` API remains appropriate.
- v0.1.0 and v0.2.0 DAG encodings need not be mutually interpretable. There is
  no known existing-user migration obligation. Do not claim a migration path
  until one is designed and verified.
- The v0.2.0 product design and README revision are intentionally deferred
  until *after* v0.1.0 is actually finalized and released. This GAW note keeps
  the agreed rationale recoverable without prematurely changing public docs.

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
semantics. Do not start them as part of release preparation.

Immediate sequence: review the v0.1.0 documentation-only freeze candidate on
project main, complete current checks and release review, let the human
perform the `NEXT -> DONE` transition and tag, then author the v0.2.0 public
semantic redesign and implementation plan. The v0.1.0 README and release notes
must continue to describe the implemented old protocol, not this future one.
