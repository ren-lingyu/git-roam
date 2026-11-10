# Git Roam current state

## Objective and production baseline

v0.2.0 is locally finalized and tagged. The user committed
build(v0.2.0): finalize release metadata as 3e6e283, after the release-guide commit
3b6d0b2. Project worktree and index are clean. The committed Cabal version and
both version-test expectations are 0.2.0; README and detailed notes contain
version prose without temporary draft/old-package claims. The user changed
CHANGELOG.org to DONE v0.2.0 with CLOSED [2026-11-10 Tue 15:29] (UTC) and matching
CUSTOM_ID. That manual state/time change was observed, not performed by the agent.

The local v0.2.0 tag is annotated (tag object
e77db7cbf0d4d1a46e84d22f2f565ab66b91c393) and dereferences to exactly this
finalized commit, 3e6e283c632e371747307c4cc2b05dbccfe8f368. Its recorded tagger
time is 2026-11-10T23:33:21+08:00 (15:33:21 UTC). Tag existence/target does not
prove platform publication, signature verification or a publication timestamp.
The user explicitly confirmed tagging and requested this memory/checkpoint
handoff without platform-publication verification. That verification is outside
this task, not a pending acceptance item or blocker. No external service was queried.
The agent did not create the project commit/tag or publish anything.

All 52 committed files were checked against the version-preparation manifest:
all are byte-identical to that tested snapshot except the exact human
NEXT -> DONE and CLOSED insertion in the root CHANGELOG. Fresh 0.2.0 compilation
and all 14 suites / 260 tests passed before commit with -Wall -Werror, one Nix
job/core and a 300s bound, without failure or timeout. Product derivation:
/nix/store/ymlx2b6s2r02a4pcqjy91kq69fcasl0n-git-roam-0.2.0.drv.
Same-source flake check reused the completed product and freshly checked 50
eligible files with zero formatting changes. The actual flake executable
returned git-roam 0.2.0 plus LF, exit 0. The final manual Org insertion received
static diff/source-identity review, not a newly executed full flake check.
Only x86_64-linux was exercised; other platform/minimum-Git/concurrency limits
remain. No unchanged tests were rerun solely to obtain a commit association.

README's Deferred candidates remain present: high-volume worktree deployment
optimization and alternative directory naming are future nonblocking work.
The user explicitly requires such plans to stay visible when preparing release
prose. Do not delete that roadmap or promote candidates into v0.2.0 guarantees.
Historical v0.1.0 notes and the explicit manual migration boundary remain intact.

The v0.2.0 tag's CHANGELOGS/v0.2.0.org is the authoritative Release Notes
manuscript for any later publication tooling. The requested local release/tag
and memory handoff is complete; await the next user objective. Do not initiate
platform verification or publication as an automatic next step. Do not re-run
A/B, restore draft wording,
repeat completed tests/experiments or add deferred features without a new task.
The ordinary temporary verification files are not required durable artifacts;
current source, tests and the associated finalized project snapshot retain the
implementation. Existing performance archives remain historical and immutable.

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

## Finalized stage C documents and remaining evidence limits

The release guide was introduced in 3b6d0b2 and finalized with package metadata
in 3e6e283. README, root CHANGELOG and detailed notes agree with the context
protocol, recursive-tree fix, non-cascading deletion, preserved worktree safety
and documented migration boundary. Root header/CUSTOM_ID are valid; the human
DONE/CLOSED record is present. The final tag points to the source containing the
complete detailed notes. The finalized documents are committed, with no
working-tree/index changes.

Stage C source/document review, the earlier isolated 250-case reproduction,
the 260-case repair/version runs and the scoped performance measurements are
complete within their stated boundaries. Use stage-c-coverage.md for the
requirement-to-test map; it describes the earlier baseline, supplemented by the
recursive-tree regression evidence above. Do not reopen an identical audit or
represent every negative case as tested in every backend/format combination.

The tested platform/toolchain is pinned x86_64-linux, Git 2.56.0/GHC 9.12.3.
Other declared systems, exact minimum Git, arbitrary concurrent writers and
literal execution of every README step remain unproven. No automatic migration,
repair, general cross-Node batch tooling or deployment acceleration is promised.

The handoff's v0.1.0 publication evidence remains historical and attributed;
this task did not independently recheck that hosted Release. Local v0.2.0
finalization/tag are independently observed and user-confirmed. Hosted
publication verification is expressly excluded from this handoff; no further
publication-status check is required to complete the current task.

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
