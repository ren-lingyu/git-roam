# Git Roam v0.2.0: caller-selected historical context

## Status and rationale

The context protocol is now the sole production protocol. The atomic cutover
replaced formal Protocol.History/Repository, CLI and installed Hook together,
adapted all lifecycle consumers and removed temporary V2 modules, tests and
aliases. Stage C local finalization is complete: package version 0.2.0, final
release documents and the human DONE/CLOSED record are committed. The observed
annotated v0.2.0 tag identifies that exact finalized source. See current.md for
test provenance and compatibility limits. The user confirmed tagging and
explicitly excluded platform-publication verification from this completed
handoff; do not treat that verification as pending release acceptance.
[current.md](current.md) gives the recoverable state and verification limits.

v0.1.0's complete exact-version knowledge-dependency DAG was an internally
coherent implementation worth preserving as a historical release. The successor
changes the meaning of parent edges deliberately; it does not recast the old
implementation as a bug or claim automatic migration. There are no known actual
v0.1.0 callers or established workflows requiring an in-place migration tool.

Git can validate that a parent points to a particular version, but cannot prove
that it is a true or exhaustive knowledge dependency. Org-roam links refer to
the current filesystem; immutable Git parents select historical versions.
Forcing those relations to stay identical creates update propagation and
cross-Node obligations. Cyclic links cannot all simultaneously name each
other's latest commit as Git ancestors. Automatically filling parents from Org
links does not remove that incompatibility.

The previous model also required external Nodes to establish formal Checkpoints
before their ordinary content could be referenced, with nonlocal retention,
deletion and successor-discard obligations. Caller-selected context removes
those obligations at the semantic level. Ordinary editing uses Content;
Checkpoints are optional when a caller wants to fix historical context.

Alternatives considered were a central aggregate snapshot branch, a separate
version/dependency manifest, automating complete Org-link declarations, and
maintaining two permanent protocols. None provides the chosen combination of
independent Node history, local context selection and native Git retention and
transport without additional coordination. Upper layers can still choose sparse,
dense or link-derived context; core neither proves nor continuously maintains it.

## Identity and commit encoding

A valid tree has one top-level canonical lowercase UUID directory containing
`.roam` as a regular or executable file. Marker bytes may change and have no
context/type semantics. Root has no parents and only that marker. Content has
exactly one same-Node parent, including empty-diff Content. The first-parent
chain establishes the Node's Root; all-parent ancestry also contains other
Nodes' Roots and is not a way to find one globally unique Root.

For a Checkpoint K:

```text
P(K) = [p, q1, ..., qn], n >= 1
T(K) = T(p)
uuid(p) = uuid(K)
uuid(qi) != uuid(K)
```

p is the immediate predecessor, which can be Root, Content or Checkpoint. Each
qi is an existing valid external Root, Content or Checkpoint, not necessarily a
current tip or retained by its own Node's present branch. All parent OIDs must
be distinct. Context trees must not overlap K's tree; with one UUID directory
per tree this means another Node. Contexts need not be pairwise different Nodes:
multiple versions of one external Node are legal, with a CLI compatibility
warning rather than protocol rejection. The stored ordered list follows CLI order.

A Checkpoint changes no content, performs no tree merge and creates no synthetic
Content. No inherited mapping or empty-context declaration exists; without
context use ordinary Content. One UUID has one Root across each validated
ancestor graph, not a global registry over remotes or unreachable objects.
Historical canonical UUID parsing is broader than new identity generation:
`node create --id` accepts UUIDv4 or Nil/Max; defaults generate fresh UUIDv4.

## Validation and Git retention

Validation starts at explicit local tips/contexts and follows actual Git parents,
with per-invocation immutable-object caches. It checks Node trees, identity,
Root consistency, parent roles/duplicates, formats, cycles and missing/wrong-type
objects. Raw cat-file sessions preserve original objects without replacement or
graft ancestry interpretation. Shallow or incomplete history is refused, not
silently treated as empty; verification does not fetch or repair evidence.

The committed recursive-tree validation repair (see current.md for verification)
starts at the UUID directory and follows every Directory through the same
readTree/entriesValid rules. A per-validation tree-OID visited set prevents
repeated traversal of shared subtrees in addition to object-read memoization.
Git.Objects connectivity checking remains separate and unchanged; it still
checks payload existence/types, including nested content. This closes the
previous gap where deeper entry names/duplicates escaped structural validation.

- firstParentHistory: the selected Node's own history.
- contextParents: one Checkpoint's direct ordered external parents.
- reachableHistory / reachableHistoryFrom: ordinary all-parent reachability;
  multiple starts share one visited set, and the singleton query delegates to it.

ManagedState is validated history plus local managed refs. It has no formal
retention set or dependency closure. A referenced context need not have a local
Node branch or remain in that branch's history. As long as a recording commit
is reachable, Git parents retain its contexts. Ordinary same-Root rewrites may
drop Content and Checkpoints; other refs, reflogs and later GC affect actual
object survival. Do not reintroduce permanent retention or specialized discard.
Uncontrolled UUID branch creation/deletion, identity changes and malformed
multi-parent histories remain refused.

## Production interfaces and execution

Post-v0.2.0 unreleased addition (implemented, tested and committed): a
prefix-only `--deploy-path ABSOLUTE` supplies the root for node create/deploy.
It is mutually exclusive with their local --path, even for identical values.
Local --path keeps its invocation-relative semantics. Other public commands
accept the prefix without using the directory; public syntax still requires an
absolute path. Internal reference-transaction dispatch ignores leading prefix
pairs without validating their values so wrappers cannot make Hook protection
depend on deployment-path validation. Hook configuration, input and validation
remain unchanged. No environment default or persistent deployment root is added.
See current.md for verification and commit status.

`checkpoint [--node UUID] (-m TEXT | -F FILE)` requires at least one repeatable
`--context REVISION`. It accepts refs and unambiguous commit OIDs, including
abbreviations, not arbitrary history/path revision expressions. It rejects
same-Node contexts, duplicate OIDs and invalid or incomplete evidence. It
constructs one commit from the existing tip's tree, conditionally advances only
that Node and preserves uncommitted index/worktree data. Failure after object
creation may leave unreachable objects; failure after ref installation reports
actual state rather than blindly rolling back.

`check` and `status` use the shared validator. Node scope inspects that Node and
its full ancestors, not unrelated branch histories; repository scope validates
all selected managed tips together. Status reports latest first-parent
Checkpoint, its direct contexts, first-parent Checkpoint count, tip kind,
Content tail and actual registered worktrees.

Main and linked worktrees infer a Node when symbolic HEAD names a canonical
local UUID branch. Ordinary branches, detached HEAD and bare repositories do not.
Inspection falls back to repository scope; Checkpoint requires an explicit Node
when it cannot infer one. The post-cutover comment/test correction documents this
existing rule; it is not a new main-worktree lifecycle feature.

The reference-transaction Hook validates at prepared, reading actual refs rather
than trusting all-zero old input. Direct Content extension/amend has a narrow
single-Node fast path; Checkpoints, arbitrary rewrites and multi-ref updates
validate the complete candidate managed set to detect external Root conflicts.
Controlled operations bypass only their own named Hook. The installed command
is PATH-resolved `git-roam --reference-transaction`; callers must use the intended
compatible executable. Application locks/expected-old/verify reduce races,
not arbitrary-process serialization or cross-worktree filesystem atomicity.

`node delete` is non-cascading: references from other Nodes do not block branch
removal. Its preview computes reachability from the target tip minus reachability
from the remaining managed tips, not physical object deletion. A main/linked
checkout blocks deletion. Confirmation binds refs, reachability, worktree records
and exact local branch config; cleanup is separate from ref deletion and failures
must report residual state. Remaining managed tips use one multi-start traversal;
this preserves the exclusive set and confirmation inputs while avoiding repeated
walks over shared ancestry.

Create/Deploy/Undeploy/Worktree reuse their existing safety machinery. Create
makes Root/branch/worktree and supports text/JSON/CBOR creation reports. Deploy
prevalidates local plus fetched candidate refs, can create missing tracking
branches, and never auto-advances existing local tips or creates a branch merely
because its historical context is referenced. Undeploy removes safe Node linked
worktrees, retaining main worktree, branches and objects. Shared deployment roots
may contain unrelated content; occupied/index-conflicting targets are refused.
Locks, dirty data, conditional transactions and conservative compensation keep
their existing boundaries. No separate registry or remembered deployment root.

## Acceptance and scope

The cutover consolidated 18 suites to 14 while preserving -Wall -Werror. Its
Protocol/Checkpoint/Inspection/Protection/Deletion/Deployment/EndToEnd coverage
is production code now, not a future V2 prototype. The handoff reports successful
user checks; no reconstruction-time build was run. Stage C must map actual tests
to required cases before filling gaps and claiming acceptance. See current.md
for the current next action, source provenance and evidence distinctions.

Keep v0.1.0 tags and notes about formal dependencies historically accurate.
Do not promise automatic migration, dual-protocol compatibility, cold-cache
performance, untested platforms or full minimum-Git compatibility.
Deployment acceleration, alternative naming/layout, .roam deployment paths
(a candidate for v0.3.0 or later), environment path defaults, cross-Node batch
tools and automatic Org-link context selection remain later work, not v0.2.0
prerequisites. The eight-character UUID
SHA-256/Base32 deployment short name remains derived, not identity metadata.
