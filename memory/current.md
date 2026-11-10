# Git Roam current state

## Objective and production baseline

Version preparation is complete; human finalization remains pending. Main is
3b6d0b2, docs: document the v0.2.0 context protocol and release changes, confirmed
after the user's commit. The current uncommitted preparation changes six files:
Cabal package version 0.1.0 -> 0.2.0, hardcoded expected version output in
Unit.hs/GitAdapter.hs, and temporary release prose in README/root CHANGELOG/
detailed v0.2.0 notes. No project staging/commit, tag or publication was performed.
The user explicitly reserves NEXT -> DONE and UTC CLOSED for manual action.

README and release notes describe version 0.2.0 without draft/pre-release or
stale 0.1.0-package claims, and without asserting publication. NEXT v0.2.0,
CUSTOM_ID, existing version states/CLOSED values and v0.1.0 notes are unchanged.
Both version-test entry points now expect git-roam 0.2.0. Feature descriptions,
manual migration boundaries and implementation logic are otherwise unchanged.

The user requires planned nonblocking improvements to stay visible in README.
Its Deferred candidates section remains byte-identical to the committed section:
high-volume worktree deployment optimization and alternative directory naming
remain future candidates, not v0.2.0 release blockers. Do not delete this roadmap
when cleaning up release prose or treat these candidates as implemented promises.

Fresh 0.2.0 compilation and all 14 suites / 260 tests passed with -Wall -Werror.
The authorized 300s build used one Nix job/core; no timeout or failure occurred.
Derivation: /nix/store/ymlx2b6s2r02a4pcqjy91kq69fcasl0n-git-roam-0.2.0.drv.
Same-source flake check passed, reusing this completed product and freshly
checking 50 eligible files with zero formatting changes. The actual default
flake executable returned exactly git-roam 0.2.0 followed by LF (exit 0).
Only x86_64-linux was exercised. All 52 isolated snapshot files were compared
against the working tree after checks. This evidence belongs to the uncommitted
version-preparation snapshot, not the 0.1.0 metadata still in main. Temporary
source manifest/logs/results are in tmp/v020-release-preparation/, not a new
archive or a required durable source. No committed version-preparation snapshot
exists yet; do not invent a project-parent association for this tested patch.

Next: the user manually changes NEXT to DONE and verifies UTC CLOSED, reviews
and stages the preparation, and commits the final version. Verify resulting
source identity and document state before grounding GAW in that commit. The
v0.2.0 tag should point at that finalized commit; no extra empty commit is needed.
Tagging and platform publication remain independent human actions. No local
v0.2.0 tag was observed after validation; no new publication check was performed.

The adopted implementation keeps entriesValid as the single entry-name rule.
Starting at the UUID directory, validateHistory walks Directory children through
readTree, with a per-invocation visited tree-OID set in addition to its read cache.
Each nested tree therefore receives the existing illegal-name/duplicate checks;
shared subtrees are walked once across paths, commits and Nodes. Blob/symlink/
gitlink payloads are not traversed as trees. Git.Objects.checkStoredConnectivity
is unchanged and retains payload existence, type and connectivity checks.

The first build compiled production code but failed -Werror=name-shadowing in
a newly added test; renaming that local binding fixed compilation. The second
build freshly compiled and passed all 14 suites / 260 test cases (-Wall -Werror):
34 protocol and 37 inspection cases, ten added groups over the prior 250-case
baseline. Tests cover invalid/duplicate nested names, missing/wrong-type subtree
evidence, and a thirty-level shared-subtree DAG on both SHA formats. Native raw
malformed trees are rejected by candidate validation, the installed Hook and
CLI check across SHA-1/SHA-256 x files/reftable. Existing connectivity and
lifecycle suites remain passing. No production Hook is installed/disabled by
these tests; only their temporary fixtures change Git state.

The user authorized on-demand 300s builds at one Nix job/core. The successful
build derivation is /nix/store/h9pnlz6cz09lr8w7kc03326yw6v2w5np-git-roam-0.1.0.drv.
Same-source flake check passed: product reused that completed build and fresh
treefmt processed 49 eligible files with zero changes. Only x86_64-linux was
exercised. The isolated 51-file snapshot in tmp/v020-recursive-tree-validation/
was byte-checked against the working tree after validation; ordinary logs and
source manifest there are not required durable evidence or a new archive.

After the user's commit, every retained source-manifest hash was compared
against its committed blob, establishing exact source equivalence without
rerunning unchanged tests. The associated project snapshot is this confirmed
repair commit, not a guessed association with its pre-repair baseline.
Resume stage C release preparation under the user's instructions. Preserve
the restored manuscript and human-only version/state/tag/publication boundaries.

The completed performance experiment remains separate evidence for unchanged
production d8503af, not a new measurement of the committed recursive-tree repair. All 36 measurements matched
semantic/full fingerprints and preserved refs. At 10,000 Nodes inspection
improved 89.570110s -> 1.706268s (60,011 -> 11 Git launches), shared query
0.936478s -> 0.060132s, and full deletion preview 8.174572s -> 4.802624s.
Its 13-file bounded archive and resource/fixture limitations are linked from
[v0.2.0-performance.md](v0.2.0-performance.md). Do not rerun the historical
patched-Git or batch-worktree experiments, as explicitly excluded by the user.

The earlier isolated stage C verification and archival assessment are complete.
That 52-file snapshot contained baseline code plus the then-staged documents. Its
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
against local project history and the then-current index on 2026-11-10. Main HEAD
at that inspection was the post-cutover follow-up, `d8503af`, after the atomic
production cutover. The project associations in inherited GAW history ground
those inspected source states; the uncommitted document draft has no project
commit association. The original handoff is input evidence, not an instruction
source that overrides current repository facts or the user's authorization.

The reconstruction horizon is accounted for: the six isolated preparations and
older release/design history were already represented; the merged AB-1/2/3
cutover and the later AB-4 follow-up each support a distinct recoverable state;
the prior C draft was observed as uncommitted work, later stashed and restored.
No supplied evidence
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
duplicate/empty starts and unknown starts. Performance was unmeasured at that
review; the later isolated results and limits are recorded in v0.2.0-performance.md.

The same follow-up corrects comments that incorrectly excluded the main worktree
from Node inference and adds actual CLI regression coverage. Both main and linked
worktrees infer a Node only when symbolic HEAD names a canonical local UUID
branch. Ordinary branches, detached HEAD and bare repositories do not infer one.
This clarifies existing inference behavior, rather than introducing a new mode.
Canonical UUID parser positive/negative coverage omitted in the cutover is restored.

The handoff reports successful user flake checks for this follow-up, not a new
agent test run. The earlier atomic-cutover implementation is inherited context;
the exact follow-up source inspection is grounded in inherited project history.

## Current stage C release manuscripts

The three-document release guide, including the nested-tree Fixed entries, is
committed as 3b6d0b2. Current working-tree changes prepare final version prose:
README names the implemented 0.2.0 context protocol; root CHANGELOG links to
Detailed release notes; detailed notes describe 0.2.0 without a transient draft
status. The README nonblocking roadmap remains intact. All are unstaged.

Root header, NEXT v0.2.0, CUSTOM_ID and historical CLOSED values remain intact.
Only the human changes existing version keywords and version-level UTC CLOSED.
Removing temporary draft prose does not finalize/tag/publish the version; the
human still needs to confirm the local DONE state. Prior migration redirection,
local-clone flow and limits of walkthrough test coverage remain intact.

Cabal is now 0.2.0 in the working tree, and BuildInfo derives --version from it.
Both version-test expectations and actual output are verified, as recorded above.
There is no automatic migration or new protocol feature in this preparation.

## Stage C next actions and acceptance limits

The memory recovery and requested independent verification/coverage assessment
are complete. Continue at C, not A/B, under the next applicable user instruction.
Use mapped coverage and the latest 260-case version-preparation result; do not
restart the same audit or treat it as every possible failure matrix. The earlier
isolated verification made no product/release writes; current version edits are
explicitly authorized and remain uncommitted. The adoption checklist remains:

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
