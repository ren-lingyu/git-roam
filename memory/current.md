# Git Roam current state

## Objective and production baseline

The atomic v0.2.0 context-protocol cutover is complete. Continue with
post-cutover review and stage C acceptance, documentation and release preparation;
do not repeat stages A/B or add parallel V2 lifecycle modules.

This snapshot reconstructs the completed production cutover from the supplied
2026-11-10 C handoff and read-only inspection of the exact historical project
commit associated with this checkpoint. It is created now, not backdated. The
six isolated preparation commits were already represented in inherited GAW
memory; the handoff supports treating the production cutover as one recoverable
state, not inventing intermediate AB-1/2/3 checkpoints or unbuildable renames.

`feat(protocol): switch production to the v0.2.0 context model` replaced the
formal Protocol.History/Repository and all production consumers together. CLI,
installed reference-transaction Hook, Checkpoint/Inspect/Delete and the existing
Create/Deploy/Undeploy/Worktree machinery use one protocol. Temporary V2 source
modules, registrations, aliases and redundant test suites are removed.

## Adopted model and public behavior

- Each Node retains a canonical UUID branch, an identity marker and a unique
  Root in the validated graph. First parents define that Node's own history.
- Root has no parents and only the UUID marker. Content has one same-Node
  parent. A Checkpoint has the immediate same-Node predecessor followed by one
  or more caller-selected external context commits, and keeps the first
  parent's tree. Contexts can be external Root, Content or Checkpoint commits.
- Context is an explicit historical selection, not a complete knowledge
  dependency mapping. No inheritance, synthetic Content, retained-Checkpoint
  set, managed dependency closure or specialized discard operation remains.
- `checkpoint` requires repeatable `--context <revision>` plus a message.
  Argument order becomes parent order. Duplicate OIDs and same-Node contexts
  are refused; different versions from the same external Node are accepted
  with a compatibility warning. Refs and unambiguous commit OIDs are supported,
  not arbitrary revision expressions.
- Ordinary valid same-Root history rewrites may drop Content and Checkpoints.
  Ordinary managed branch creation/deletion and Root changes remain refused.
- `check` validates selected tips and all their ancestors; `status` reports the
  latest first-parent Checkpoint's direct contexts. External contexts do not
  require corresponding local branches or current-branch retention.
- Node deletion is non-cascading. Its preview reports commits losing reachability
  from the remaining managed refs, not physical Git object deletion. Checkouts,
  reviewed plan IDs, conditional refs and exact local config cleanup still apply.

See [context-checkpoint-direction.md](context-checkpoint-direction.md) for
rationale, structural rules and application boundaries. Preserve the v0.1.0
model as historical design, not a compatibility layer.

## Safety and verification evidence

The Hook validates at `prepared`, reads actual managed refs and processes a
complete candidate transaction. Only direct Content extension/amend may use a
single-Node fast path; Checkpoints and general rewrites use whole-state
validation to detect cross-branch Root conflicts. Controlled operations bypass
only their own named Hook, and retain operation locks, expected-old/verify
transactions, worktree safety, conservative compensation and residual reporting.
These do not establish arbitrary-process serializability or filesystem atomicity.

The cutover consolidates 18 Cabal suites into 14, with `-Wall -Werror` on all
components. Protocol, Checkpoint, Inspection, Protection, Deletion, Deployment
and real-CLI/installed-Hook EndToEnd tests were migrated. Their presence does
not prove every stage C failure matrix was rerun. The supplied handoff reports
the user's successful pre-commit `nix flake check`; this memory reconstruction
performs source inspection only, not a new build or test run. Original test
execution provenance is not inferred merely from a nearby commit. The exact
project association grounds the inspected implementation, not a newly executed
post-commit check.

Earlier 18-suite/306-case evidence belongs to isolated preparation. Earlier
v0.1.0 counts and object-reader timings remain historical evidence, not tests or
performance guarantees for this new protocol. Pinned x86_64-linux evidence does
not establish all declared systems or exact minimum-Git compatibility.

## Stage C and release boundary

At this implementation boundary Cabal still declares 0.1.0 and committed README
and CHANGELOG still describe pre-cutover production. Stage C must align them
with actual context semantics, audit coverage through the real CLI and Hook,
and complete release preparation. Implemented protocol is not published release.

1. Map existing tests to context kinds/order, anchoring after external rewrite or
   deletion, Root conflicts, native rewrites, conditional/multi-ref protection,
   deletion safety and worktree failure behavior. Fill verified gaps only.
2. Align README, help, CHANGELOG and detailed v0.2.0 notes; preserve historical
   v0.1.0 notes. Separate committed source from any later staged document draft.
3. Coordinate the human-owned TODO/NEXT/DONE lifecycle and package version,
   verify authorized final source/checks, and distinguish tag creation from
   GitHub publication. Do not fabricate release times, migration or compatibility.

Deployment acceleration, naming/layout or .roam deployment metadata, environment
path defaults, cross-Node batch tools and Org-link automation are separate future
work. They are not reasons to expand this protocol cutover or stage C.

## Navigation and retained history

- [context-checkpoint-direction.md](context-checkpoint-direction.md): current
  context protocol, decisions and production execution boundaries.
- [design.md](design.md): historical v0.1.0 complete-dependency design.
- [implementation.md](implementation.md): completed v0.1.0 serial milestones
  and their execution constraints, not the active development schedule.
- [raw-reader-implementation.md](raw-reader-implementation.md),
  [object-reader-performance.md](object-reader-performance.md): scoped raw-reader
  architecture and original source-specific measurements; no v0.2.0 speed claim.
- [native-git-validation.md](native-git-validation.md) and
  [experiment.md](experiment.md): historical isolated experiments and their limits.

The previous long current.md remains intact in inherited first-parent history,
including all serial milestone checks, capability additions and V2 preparation
observations. This concise state removes superseded next-action instructions
without rewriting those checkpoints or the original archives. Existing design,
implementation and dedicated evidence files retain the substantive old records.
The user-supplied root handoff is a reconstruction input; necessary conclusions
are distilled here rather than depending on that temporary file staying present.
No raw transcript archive or new source-history branch is required.

The project skill remains a stable navigation entry. GAW checkpoints and product
Checkpoints are distinct. This memory does not authorize project staging,
commits, tags, publication or unrelated tests; follow the active user scope.
