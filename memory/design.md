# Git Roam current design

## Status and purpose

The user adopts the settled decisions in the supplied design document as the
current effective design for subsequent implementation. This is a current
knowledge baseline, not a reconstruction of design history. Reasons below
explain constraints that still matter. Implementation status and unresolved
interfaces are separate in [implementation.md](implementation.md); actual
repository state and navigation are in [current.md](current.md).

A Node represents an independent knowledge bundle with its own traceable Git
history. A formal knowledge state records the exact versions of other Nodes
needed to interpret it, while ordinary editing continues through files,
editors, and native Git. Org-roam motivates this use case but does not define
the core format. These product rules do not replace GAW's own protocol or the
user's execution/authorization policy.

## Identity and Git object model

Let `P(x)` be the ordered Git parents of commit `x`, `T(x)` its tree OID,
`R_u` the Root of UUID `u`, `W` a Content commit, and `K` a Checkpoint.

Each Node has one authoritative active local branch, conventionally
`refs/heads/<uuid>`. Branch spelling, note titles, classification, and deployment
paths are not proof of identity: validate the Root, UUID subtree, and history.
Keeping one branch avoids two independently managed authoritative histories.

Create UUIDv4 identities and check known active identities and relevant
reachable history for conflicts. The same UUID must not identify incompatible
Roots in the retained knowledge. This is a local, visible-history guarantee,
not mathematical uniqueness across unsynchronized clones or forgotten history.
Do not silently combine different Roots or rewrite identity to resolve a clash.

### Root and Content

A Root has no parents. Its complete tree is only `<uuid>/.roam`: one UUID
directory containing a regular-file marker, with no body or dependencies.
The marker is a file, not a directory or mandatory classification record.
Creation may emit an empty blob, but nonempty historical markers are not
invalid merely because of their content. Stronger marker blob/mode protection
is an operational choice, not an empty-blob history invariant.

Content has exactly one parent, keeps the same sole top-level UUID subtree,
and retains its regular-file marker. Additional Node directories or content
outside that subtree are invalid. Before the first Checkpoint, Content forms
a single-parent chain to the Root; after a Checkpoint, new Content starts
from that Checkpoint and continues as a single-parent chain.

Core validation is Git-only. It does not require `note.org`, Org syntax or IDs,
a nonempty body, a particular number of payload files, or a nonempty diff.
An empty-diff non-Root Content commit is still distinct from the Root.
Org semantics may be added through a separate adapter without changing this
Git history protocol.

Native Git creates and edits Content. Git Roam does not wrap `git add`,
ordinary `git commit`, amend, reset, or rebase with replacement editing commands.

### Checkpoint structure and continuity

For later Checkpoints:

```text
P(K_i) = [K_(i-1), W_i, d_1, ..., d_n]
T(K_i) = T(W_i)
```

For the first Checkpoint, replace the first parent with `R_u`. The second
parent must be a non-Root Content commit of the same Node. Third and later
parents, if any, are valid Checkpoints of other Nodes. Every Checkpoint
therefore has at least two parents.

The first parent is the previous formal state and defines the ordered formal
history; the second is its recognized committed content; the remainder are
precise external knowledge dependencies. This fixed role split lets ordinary
Content history and formal history coexist on one branch.

Adjacent Checkpoints must satisfy exactly one of these continuity cases:

- No new Content: reuse the identical second-parent Content commit.
- One or more new Content commits: the first has the preceding Checkpoint as
  its sole parent, subsequent Content commits each parent the preceding Content,
  and the new Checkpoint's second parent is the last commit in this chain.

The first Checkpoint requires at least one Content commit whose sole-parent
chain reaches the Root. Do not choose unrelated old forks as content sources.
Reintroducing older text through new legal commits is allowed; continuity is
about history, not whether payload bytes are novel. In the nonzero case,
traversal back to prior content passes through the previous Checkpoint and its
second parent, not an uninterrupted Content-only parent chain.

### External dependencies

A Checkpoint stores its complete direct dependency set. Map each external
UUID to at most one exact Checkpoint: no self-dependency, duplicate UUID with
multiple direct versions, or Root/Content dependency targets.

Targets need not be the external Node's latest Checkpoint. Indirect histories
may legitimately contain different versions of a Node; do not impose one
global version across the transitive closure. Text links/backlinks do not
automatically create formal dependencies.

External parents are semantically an unordered set. The current creation
strategy sorts them by UUID for deterministic construction, but valid history
does not require this order. First and second parent roles remain ordered.

## Creating formal state

Creation defaults to the previous Checkpoint's complete dependency mapping,
or an empty mapping for the first Checkpoint. One operation can add, remove,
and replace multiple dependencies: remove requested entries, then apply the
additions/replacements. Validate the complete final map and conflicting inputs
before advancing the Node ref. Every target must exist, be an appropriate
external Checkpoint, and have a still-retained, nonconflicting identity.
Any invalid request leaves the ref unchanged.

Inheritance is a creation convenience, not an implicit historical rule:
the new commit itself always carries all final external dependencies.

Choose content solely from the validated current branch tip:

| Tip | New Checkpoint second parent |
| --- | --- |
| Root | Reject: a non-Root Content commit is required first |
| Content | That exact tip |
| Checkpoint | That Checkpoint's existing second parent |

Read that Content commit's existing tree; do not call `write-tree` to synthesize
a new snapshot from the index. A dirty index/worktree is allowed. Staged,
unstaged, and untracked files are not included or altered. Feedback should
identify the selected Content OID so users can see what was formalized.

Under the structural lock, validate state/dependencies, read the Content tree,
construct the commit using `git commit-tree` with exact parent order, and
advance the ref using `git update-ref <ref> <new> <expected-old>`.
A stale comparison must fail without overwriting the competing update.
An unreachable newly written object may remain after failure; no partial
formal ref update may become effective. Single-ref atomicity is not a
distributed transaction or atomic worktree deployment.

## Native Git protection and concurrency

Define `anchor(H)` by walking the sole-parent Content tail from tip `H` to
its nearest Checkpoint, or to its Root if no Checkpoint exists. A native ref
update must preserve `anchor(new) = anchor(old)`, with only legal Content
between the new tip and that anchor and valid Node trees along the path.

This permits ordinary commits, tail-only amend/rebase, and reset to the latest
Checkpoint or its Content descendants. It rejects dropping an established
Checkpoint, amending the latest Checkpoint, native multi-parent merge commits,
and uncontrolled deletion of an active Node branch. Judge fast-forward-only
merge by its resulting history, not the command's name.

The reference-transaction Hook adapter and explicit checker must share history
validation with controlled operations. Distinguish Node branches, unrelated
branches, remote-tracking refs, symbolic HEAD updates, and pure HEAD switches;
check actual ref state rather than trusting only an input old OID. Reject
corrupt or indeterminate protected history conservatively. A routine Content
update checks the anchor/new path, not the entire external dependency graph.

Managed operations validate first and bypass only Git Roam's own corresponding
named hook during their controlled ref update. Other hooks must remain effective.
Installation is local configuration, not something clone/fetch/push automatically
activates. Hooks prevent ordinary misuse; they are not a hostile-user security
boundary. Exact integration/compatibility details remain implementation work.

Use one repository-wide OS-level mutex associated with the Git common directory
for Node creation, admission of existing history, Checkpoint creation, and
deletion. All managed structural entry points participate. Worktrees share the
lock, which is local operational state, not a committed protocol object or
permanent locking ref, and must release after process termination.

Ordinary Content commits do not add dependency edges and need not acquire it.
Different Nodes can be edited concurrently. For a Content/Checkpoint race on
the same ref, expected-old comparison rejects stale updates. The structural
lock prevents dependency creation racing a deletion scan. It supplies no
cross-clone lock or distributed guarantee.

## Deletion and admission

Delete a Node's active branch only if no historical Checkpoint of any other
retained active Node directly depends on that Node. Scanning only latest
Checkpoints is insufficient. Its own Checkpoints or outgoing dependencies do
not prohibit deletion if no such incoming edge exists.

Deletion does not rewrite other Nodes, cascade through the DAG, create a
tombstone/retired identity registry, or promise physical erasure of Git objects.
Handle associated worktrees without destroying user data, and condition ref
deletion on the expected old OID. The same UUID may become reusable after it
is absent from all retained relevant knowledge, but later synchronization with
an older clone can reveal a conflict; never claim global uniqueness.

Fetch remains native Git's responsibility. Objects and remote-tracking refs
do not automatically create local active branches. Deployment may admit fetched
candidate history when a local Node branch is absent: fully validate its Root,
history, required external closure, and identity compatibility, then establish
the active ref under the structural lock and deploy the worktree. If a local
branch already exists, reject incompatible candidate histories rather than
merging or forcing them. Admission creates no permanent import state.

## Deployment and validation boundaries

A Node tree fixes its UUID subtree, not filesystem placement or classification.
Deployment/undeployment do not rewrite knowledge history. Optional `main`
content may generate deployment instructions using Nix or scripts; it is not
a central authoritative knowledge snapshot and may be replaced independently.

Batch deployment should preflight the complete manifest for duplicate UUIDs,
path conflicts, occupied branches, unsafe paths, and user-file overwrites, and
report failures. Short deployment names carry no identity semantics; the
candidate manifest and naming algorithm are in
[implementation.md](implementation.md), not permanent history invariants.

Tailor verification to the operation: routine Content updates inspect anchors
and paths; Checkpoint creation inspects the current Node/final dependencies;
admission validates necessary history and external closure; explicit checking
supports selected Node or repository scope; deletion scans retained historical
incoming edges. Cache immutable commit OIDs within one validation to avoid
rechecking shared dependencies. Graph traversal is O(V+E), plus Git object/tree
I/O; it needs neither full checkouts nor Org parsing.

Start without a permanent global dependency/identity index. Derived views may
later be disposable caches, never a second authority. Infrequent deletion can
use correct scans before performance evidence warrants indexing. Batched object
reads or Git commit-graph may optimize access, not replace protocol validation.

Standard Git plumbing is the protocol implementation direction. Patched Git
is optional deployment acceleration, not a prerequisite for interpreting Node
history. The verified worktree experiments and their limits are maintained in
[experiment.md](experiment.md).

## Source and adoption boundary

Distilled from the user-supplied `git-roam-design-2026-10-31.org` member of
`tmp/git-roam-v0.1.0-design-and-experiment.zip`; the user explicitly confirmed
that its settled decisions are the current effective design. The member is
43390 bytes, SHA-256
`d65ec4e2253e2e2f839780832382d8e0c4cd08923280e6f6df29631ce3b2f953`.
The ZIP SHA-256 is
`d63547595d2de0bed3b4a3745c173a470a1deaea999a7d7e4a80f9ad44b19485`.

This memory is self-contained current knowledge, not a raw-document archive,
chronology, or claim that referenced historical experiments were repeated.
Implementation remains separate. Changes that affect permanent parent/tree
semantics need an explicit design decision, not an undocumented implementation
shortcut.
