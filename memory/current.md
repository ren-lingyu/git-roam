# Git Roam current state

## Objective and production baseline

Current user task: run new isolated v0.2.0 performance experiments and assess
archival value. Work is in tmp/v020-performance/, based on committed d8503af,
with legal context DAGs for 1,000/10,000 Nodes. Compare one-shot/persistent raw
reads, single-start-union/multi-start queries and complete deletion previews.
The user explicitly said not to rerun historical patched-Git or batch-worktree
experiments; reuse their existing evidence only. See
[v0.2.0-performance.md](v0.2.0-performance.md) for controls, execution and limits.
Both scales and workloads completed: 36 successful paired measurements with
matching semantic/full digests and unchanged refs. At 10,000 Nodes inspection
improves 89.570110s -> 1.706268s (60,011 -> 11 Git launches); shared loaded-graph
query 0.936478s -> 0.060132s; actual full deletion preview 8.174572s -> 4.802624s.
Keep query and full-preview ratios distinct. No OOM/measurement timeout.
Selective archival assessment is complete; 13 small byte-verified recipe/report/
result files are retained in the snapshot linked from v0.2.0-performance.md.
Project main/index/source and old archives remain unchanged. No product patch
is needed from these results. Resume stage C acceptance on user instruction.

The user's isolated stage C verification and archival assessment are complete.
The 52-file snapshot contains main code plus the three staged documents. Its
original flake check passed (existing package result plus fresh document format
check on 50 eligible files). A separate isolated derivation, changing only
preCheck/postCheck markers around the actual Cabal test wiring, freshly compiled
and passed all 14 suites / 250 cases with -Wall -Werror and Nix exit 0.
The first 120s attempt stopped after 169 passing cases; a separately authorized
one-time 300s rerun completed. No observed case failure or product patch.

[stage-c-verification.md](stage-c-verification.md) records actual execution,
provenance, timeout history and limits. [stage-c-coverage.md](stage-c-coverage.md)
maps C requirements to maintained tests; 91 function locators were checked.
Required semantic groups have coverage, but not every negative case/backend
cross-product, every README line, exact minimum Git or other platforms. Archival
assessment declined a new raw snapshot: recoverable source and ordinary logs
add no independent evidence need; durable conclusions and coverage are retained
in memory. No project source/index/refs or original archives were changed.

The atomic v0.2.0 context-protocol cutover is complete. Post-cutover
reachability/inference regression review is also complete. Continue stage C
acceptance, documentation and release preparation;
do not repeat stages A/B or add parallel V2 lifecycle modules.

The supplied root file git-roam-v0.2.0-handoff-C-2026-11-10.md was reviewed
against local project history and the current index on 2026-11-10. Main HEAD is
the inspected post-cutover follow-up, `d8503af`, immediately after the atomic
production cutover. The project associations in inherited GAW history ground
those inspected source states; the uncommitted document draft has no project
commit association. The original handoff is input evidence, not an instruction
source that overrides current repository facts or the user's authorization.

The reconstruction horizon is accounted for: the six isolated preparations and
older release/design history were already represented; the merged AB-1/2/3
cutover and the later AB-4 follow-up each support a distinct recoverable state;
the current C draft is observed as uncommitted work. No supplied evidence
establishes separately committed AB-1/2/3 intermediate states or newly executed
checks, so none is invented. Recovery checkpoints are created now, not backdated.

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
the user's successful pre-commit `nix flake check`; the preceding handoff
reconstruction used source inspection only. The current isolated reproduction
has its own completed independent execution record at the top of this file. Original test
execution provenance is not inferred merely from a nearby commit. Earlier
reconstruction associations grounded source inspection; the independent execution
completed in this task is recorded separately above.

Earlier 18-suite/306-case evidence belongs to isolated preparation. Earlier
v0.1.0 counts and object-reader timings remain historical evidence, not tests or
performance guarantees for this new protocol. Pinned x86_64-linux evidence does
not establish all declared systems or exact minimum-Git compatibility.

## Completed post-cutover review

`perf(protocol): avoid repeated ancestry walks across multiple starts` adds
reachableHistoryFrom: all supplied starts share one visited set, so common
ancestors are traversed once. The singleton reachableHistory delegates to it.
Delete.collect uses this multi-start query for remaining managed tips during
preview and execution-time plan reconstruction. Exclusive reachability and the
confirmation-token inputs are unchanged; this is not a new protocol or deletion
policy. Tests cover equivalence to single-start closure unions, shared ancestry,
duplicate/empty starts and unknown starts. No measured speedup is claimed.

The same follow-up corrects comments that incorrectly excluded the main worktree
from Node inference and adds actual CLI regression coverage. Both main and linked
worktrees infer a Node only when symbolic HEAD names a canonical local UUID
branch. Ordinary branches, detached HEAD and bare repositories do not infer one.
This clarifies existing inference behavior, rather than introducing a new mode.
Canonical UUID parser positive/negative coverage omitted in the cutover is restored.

The handoff reports successful user flake checks for this follow-up, not a new
agent test run. The earlier atomic-cutover implementation is inherited context;
the exact follow-up source inspection is grounded in inherited project history.

## Current stage C document state

The project source and tests match main HEAD; only these three documents are
staged, with no unstaged changes to them:

- README.org: context-based user guide, explicit --context examples, main/linked
  inference, ordinary rewrites, non-cascading deletion and safety boundaries.
- CHANGELOG.org: user-visible Removed/Changed/Added summary under NEXT v0.2.0.
- CHANGELOGS/v0.2.0.org: newly staged draft detailed release notes, not present
  in main HEAD.

Committed README and CHANGELOG still describe pre-cutover behavior. The staged
manuscripts are not committed release facts. The current index has NEXT,
CUSTOM_ID: v0.2.0 and text stating version/scope are frozen but not finalized,
tagged or published. The handoff's older warning about missing CUSTOM_ID and
contradictory 'not frozen' text is superseded by this directly observed, internally
consistent draft. Do not reintroduce that stale blocker or change the human's
version state. During the preceding reconstruction, staged diff --check passed
but no build/acceptance run occurred. The current reproduction record above
supersedes that earlier verification boundary. Newly staged notes are tracked by the index,
so the handoff's untracked-source warning is no longer their present status.

The draft already corrects migration example redirection, a local clone example
that unnecessarily depended on push, and the claim that EndToEnd replays every
walkthrough step. Keep those corrections; do not gratuitously rewrite the notes.

Cabal still says version 0.1.0, and BuildInfo derives --version from Cabal. The
staged README explicitly explains that transitional metadata; it is not an
in-place migration mechanism. Package version and corresponding output need
release-time coordination. There is no local v0.2.0 tag observed and no verified
v0.2.0 GitHub publication evidence in this review.

## Stage C next actions and acceptance limits

The memory recovery and requested independent verification/coverage assessment
are complete. Continue at C, not A/B, under the next applicable user instruction.
Use the mapped coverage and actual 250-case result above; do not restart the
same audit or treat it as every possible failure matrix. Product/release writes
were not included in this verification task. The adoption checklist remains:

| Area | Evidence to map or complete |
| --- | --- |
| Context DAG | External Root/Content/Checkpoint, order, duplicate/self rejection, repeated-external-Node warning, same-tree direct Root Checkpoint. |
| Historical anchoring | Context after external advance/rewrite/branch deletion, no propagation or requirement to create an external Checkpoint. |
| Identity/objects | UUID and Root conflicts, marker/tree shape, missing/wrong-type objects, shallow history, raw replace/graft boundaries. |
| Native updates | Content/amend/same-Root rewrite, invalid multi-parent updates, Root change and uncontrolled UUID ref creation/deletion. |
| Transactions | Whole prepared candidate, expected-old races, other Hooks, operation locks/config, failure residuals. |
| Delete | Non-cascading context retention, managed-ref exclusive reachability, main/linked checkout refusal, stale token and exact config cleanup. |
| Worktrees | Dirty index/untracked/ignored data, nesting/move/locks, main preservation, remote ambiguity and conservative compensation. |
| Matrix | SHA-1/SHA-256, files/reftable and relevant main/linked/bare cases; name actually exercised Git/platform versions. |

Then align help, README, root CHANGELOG and detailed notes to actual code;
confirm intended version, authorized checks and source inclusion. Only the human
performs project staging/commits, existing release-state transitions and UTC
CLOSED review, tags and publication. A tag must identify the intended finalized
source/notes, and GitHub publication is a separate observable event. Preserve
v0.1.0 notes and code rather than reinterpreting their formal dependencies.

Local v0.1.0 annotated-tag dereference was confirmed as the historical finalized
commit. The handoff reports an existing v0.1.0 GitHub Release published at
2026-11-08T09:59:33Z and supplies its public release URL; the public API read in
this consolidation was unavailable, so that timestamp remains attributed to
the handoff, not new independent publication verification. No release operation
was performed. Do not confuse absent fresh verification with proof of absence.

Deployment acceleration, alternative naming/layout or .roam deployment metadata
(v0.3.0 or later candidate), environment deployment-path defaults, cross-Node
batch tooling, Org-link automation, automatic v0.1.0 migration and permanent
context-retention policy are outside this release task. Existing create/deploy
still explicitly require --path. No new benchmark or platform guarantee follows
from the ancestry optimization or earlier v0.1.0 experiments.

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
