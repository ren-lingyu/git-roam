# Git Roam current design

## Authority and scope

This is the effective v0.1.0 design adopted through the user's final decisions
and accepted implementation plan on 2026-11-01. The earlier supplied design
document was the initial knowledge source; the final decisions supersede its
conflicting assumptions. This is current memory, not a replay of design history.
See [implementation.md](implementation.md) for the accepted execution sequence
and technical validation gates, and [current.md](current.md) for actual progress.

Git Roam represents independent knowledge bundles and their exact dependencies.
Knowledge construction, dependency changes, integration, and discard are local
Git repository operations. Clone/fetch/push transmit existing objects and refs;
synchronization does not automatically construct, merge, or rewrite knowledge.
This document defines the intended design; current.md records the implemented
subset and its verification limits.
The product protocol does not redefine GAW or extend execution authorization.

## Standard knowledge model

The fully non-sparse local model is the semantic reference model. A formal
knowledge version C has UUID uuid(C), complete content tree T(C), same-Node
direct formal predecessors H(C), and complete direct external dependencies D(C).

Every formal version explicitly declares all direct dependencies, including an
empty set. Dependencies identify exact formal versions of other Nodes; each
external UUID has at most one direct version. Transitive contexts may contain
different versions of the same Node: there is no global version-unification rule.
H(C) may contain multiple same-Node predecessors, permitting formal convergence.
Formal predecessors and external dependencies have distinct meanings.

The standard model concerns formal versions, not every ordinary editing commit.
Content/Checkpoint is a concrete encoding retaining editing history in addition
to formal semantics; it is not itself the fully non-sparse reference model.

## Identity and permanent Git encoding

Let P(c) be the ordered Git parent list and T(c) the tree OID. UUIDs use canonical
lowercase hyphenated text. Every valid Node commit has exactly one top-level
directory, named for its UUID, containing the regular-file marker <uuid>/.roam;
nothing outside that directory is permitted. Content and Checkpoint trees may
also contain arbitrary knowledge payload within that directory.

The Root establishes identity. In valid history, following first parents reaches
the same-Node Root, whose tree supplies the UUID marker. Full Git ancestry also
contains external Nodes' Roots and cannot identify a unique Root for this purpose.
Validate every relevant commit's tree and same-Node history, not just the branch
name. A UUID-looking name alone does not prove valid history.

Create UUIDv4 identities and zero-byte regular-file markers. Historical marker
contents need not be empty; marker bytes carry no type/version/dependency meaning.
Preserve marker path and regular-file type. No mandatory note filename, Org
syntax, Org ID, nonempty payload, or nonempty diff follows from this protocol.
Same-UUID relevant history must have one consistent Root; reject conflicts rather
than selecting, rewriting identity, or merging them. UUID uniqueness is local to
known history, not a global guarantee or permanent retirement registry.

### Root and Content

Root R_u has no parents and its complete tree is only <uuid>/.roam. It establishes
identity, contains no knowledge payload, and is not a formal Checkpoint.

Content W has exactly one same-Node parent, which may be Root, Content, or
Checkpoint. Content chains may fork. A Content commit retains editing history
but is not an independent standard-model formal version: its formal dependency
set is undefined, not empty and not inherited from a previous Checkpoint.

Native Git supplies ordinary editing, staging, commits, amend, reset, rebase, and
squash. Git Roam does not replace that workflow or impose a Content message
format. Empty-diff Content is valid.

### Checkpoint and projection

For a Checkpoint K:

    P(K) = [q, w, p3, ..., pn], n >= 2
    T(K) = T(w)

q is the same-Node Root or Checkpoint, the formal main predecessor. w is a
same-Node Content commit; following its sole-parent Content chain must terminate
at q. All additional parents are valid Checkpoints. All parent OIDs are distinct.
The first two positions have permanent roles; extra-parent ordering does not.

Partition the additional Checkpoints by UUID:

    M(K) = same-UUID Checkpoints among p3, ..., pn
    D(K) = parents whose UUID differs from uuid(K)
    H(K) = M(K) union {q}, when q is a Checkpoint
           M(K), otherwise

M(K) retains other same-Node formal histories, not external dependencies.
Each external UUID occurs at most once in D(K). Every same-Node formal predecessor
has the same Root. Root/Content cannot be external dependency targets.

Projection to the standard model preserves H(K), D(K), and T(K). The second
parent and intermediate Content commits preserve the editing process but do not
project to separate formal versions. The validator must accept valid same-Node
multi-predecessor Checkpoints even though v0.1.0 has no general merge constructor.
Parent count alone never establishes validity.

With this encoding, Git ancestry between valid Checkpoints equals transitive
reachability through H union D (including equality). It does not equal H-only,
same-Node formal ancestry. The Content second-parent path returns to q and adds
no other formal predecessor.

## Managed reference state and closure

A managed Node uses one persistent local branch refs/heads/<uuid>, whose name
must match its validated identity. R maps managed UUIDs to their tips; tips may
be Root, Content, or Checkpoint. Enumerate canonical UUID branch names, validate
them, and report malformed histories rather than silently excluding bad refs.
Unrelated branches, tags, remote-tracking refs, and symbolic HEAD are distinct.

K_u(R) is the complete same-Node formal history retained by R(u): follow a
Content's sole parent; at a Checkpoint record it and follow q and all M(K);
stop at Root. Do not follow foreign dependencies to compute K_u.
K(R) is the union over managed Nodes.

For each retained K, all H(K) and D(K) must be retained; each d in D(K) must belong
to K_uuid(d)(R). Dependencies may select old versions, not only branch tips.
Object reachability alone does not substitute for the required persistent branch.
Refs outside the managed set do not grant formal retention merely by keeping
objects reachable. No Node active/inactive lifecycle or separate Node registry
exists. Worktrees do not determine managed membership.

Required objects must be locally available for complete validation. Missing
objects, shallow boundaries, or other incomplete evidence cannot be accepted as
a complete valid history; distinguish those conditions from proven violations.
Recovering a lost original branch tip from residual objects is outside v0.1.0.

## Ordinary protection, coordination, and checking

Ordinary updates preserve all established formal versions per existing Node:

    K_u(R) is a subset of K_u(R')

This includes unreferenced and old Checkpoints. Native Git may introduce valid
new Checkpoints and adjust unconfirmed Content, including legal non-FF Content
changes. Git fast-forward alone is insufficient; inspect UUID-aware formal
retention and valid target history. Anchor equality is only a possible local
shortcut for a restricted Content transition, not the complete protection rule.
Reject ordinary managed branch deletion and uncontrolled new managed branches.
Controlled creation may occur inside deploy as described below.

Use a shared validator for check, Hook, and application plans. Check is the
public complete protocol validation entry; status reports actual history,
dependencies, deployment, and diagnostics. For Content tips, label any displayed
dependencies as those of the latest Checkpoint, not dependencies of Content.

Separate current-state checks, candidate-state checks, local safety, and realtime
reference protection. Enable has no knowledge-validity precondition. Deploy can
turn an incomplete current local branch set into a valid target set.
Ordinary local Content checks need not rescan the entire repository.

Use a named configured reference-transaction Hook, coexisting with other hooks.
Evaluate complete proposed transactions in a rejectable phase, using actual ref
state rather than assuming zero old OID always means creation. Handle symbolic
HEAD and unrelated refs separately. A managed invocation may authorize or disable
only its own Hook after independent validation; never disable all hooks.
Protection prevents ordinary mistakes, not hostile-user bypass.

Coordinate controlled operations at Git common-directory scope; use expected-old
updates and, where useful, transaction verify for read dependencies. Types and
application locks do not freeze external Git state. Multi-ref transactions do
not provide atomic snapshots to all readers. v0.1.0 targets correctness under
declared supported conditions, not arbitrary external-writer serializability.
Distinguish rejection, unstable observation, Git failure, and post-commit anomaly.
Postchecks are detection, not automatic rollback or recovery.

## Protection lifecycle

Enable installs/activates this repository's protection. It creates no repository,
knowledge commit, Node, worktree, registration state, or closure repair.
It can run in any knowledge-history state; installation conflicts and unsupported
Git features can still fail. Correct repeated enable is safe.

Disable removes only Git Roam's protection configuration, after full undeploy has
completed. It retains branches, objects, identities, and histories. Undeploy does
not uninstall protection. Other modifying commands require healthy protection;
check and status do not. There are no init/deinit commands.

## Node creation, tracking branches, and full deployment

Node create requires --path and creates UUIDv4, valid Root, local UUID branch,
and linked worktree, returning full UUID and actual path. It is not a branch-only
operation. This one-Node creation does not add subset selection to normal deploy.

There is no independent node adopt command. Normal clone/fetch can be followed by
enable and deploy. Deploy may establish missing local UUID tracking branches for
already fetched valid history, using native worktree/tracking behavior where
safe. It is therefore not strictly read-only with respect to R.

Candidate discovery uses canonical UUID local heads and canonical remote-tracking
names, not arbitrary refs or an object-database scan. Local branches take priority
and are never advanced by deploy. A sole remote source is usable; equal-OID sources
may coalesce; distinct tips require explicit remote selection. User Git defaults
must not silently override this ambiguity policy. If Git guessing still rejects
equal-OID sources, explicitly supply a selected starting ref. Do not infer the
latest remote branch tip from a dependency Checkpoint.

Validate the complete target branch set and all necessary dependencies before
controlled creation. Mutually dependent new branches may need a joint conditional
ref transaction rather than unvalidated intermediate worktree-add operations.
This technical coordination does not justify restoring a public adopt interface.
Deploy does not fetch, merge divergence, reconstruct, or discard Checkpoints.

Normal deploy targets all current and selected newly established Nodes, not a
user-selected subset or dependency expansion at a historical version. Recognize
existing valid linked worktrees at their actual paths, including manually created
and moved ones; do not migrate them to match the current --path. Partial actual
deployment may exist after creation, fetch, or failure; full is the command goal,
not a repository invariant.

### Paths, worktree scope, and undeploy

All newly created Node worktrees use explicit --path, then <path>/<short(uuid)>.
The tree within the worktree retains the full UUID directory.

    canonical lowercase hyphenated UUID ASCII
      -> SHA-256 -> first 5 raw digest bytes
      -> RFC 4648 standard Base32 -> lowercase -> no padding

The result has eight characters. Detect collisions; do not silently lengthen or
substitute names. Short names are derived path components, not identity or a
separate persistent mapping. Git records actual paths; do not reverse-map them
using the current short-name algorithm.

The deployment root may be inside a main or linked worktree, but cannot equal an
existing worktree root. First use requires absent/empty directory. Nested roots
must be wholly protected by applicable Git ignore rules; never edit outer ignore
configuration automatically. Reuse may contain valid existing Node worktrees,
not unrelated files/directories/worktrees. Check path and symlink safety,
collisions, occupancy, locked/prunable states, ignored data, and nesting.

All linked worktrees attached to canonical managed branches are deployment
targets regardless of creator or location. Undeploy discovers all of them from
Git, needs no --path, and changes no Node branch or Hook. Unsafe preflight for
any target rejects the whole operation. Main worktrees are not automatically
removed, cleaned, or switched; report their Node checkout as a special conflict.
Detached worktrees are not normal Node deployments. Historical checkout is deferred.

Do not keep previous deployment roots, classify Nodes by directories, or maintain
CSV/classification mappings. Re-deploy does not restore former manual layouts.
Upper-level tools may provide knowledge classification and navigation.

Execution can fail after partial worktree progress. Compensate only this
invocation's newly created, unchanged, safely removable state; preserve prior
worktrees and user changes. Branch compensation also must preserve final closure.
Never equate newly created/unchanged with safe branch deletion. Report completed,
remaining, and uncompensated changes accurately, without filesystem atomicity claims.

## Constructing Checkpoints

The accepted implementation plan requires Content before the first Checkpoint
when tip is Root. With Content tip, use its exact committed tree. With Checkpoint
tip, write a new empty-diff Content object with that Checkpoint as sole parent,
then use it as w; do not reuse the old second parent. Advance only the final
Checkpoint ref with its original expected-old.

Default the dependency configuration to the prior Checkpoint's complete mapping
(or empty before the first), then apply clear/remove/add/replace requests and
validate the full result. Inheritance is construction convenience, not permanent
delta semantics. Create a commit-tree object with exact parents and tree;
do not synthesize content using write-tree, auto-squash, or inspect Org semantics.
Dirty index, working files, and untracked data are excluded and remain unchanged.

Checkpoint dependency inputs are Git refs or unambiguous commit OIDs (including
unique hexadecimal abbreviations), not the full Git revision expression language.
Git resolves names; raw stored tag headers may peel annotated tags to commits.
Knowledge relationships and completeness use original commit/tree edges and blob
metadata with replacement objects disabled. Do not use GIT_GRAFT_FILE or
advice.graftFileDeprecated, and do not introduce a temporary Git repository view
for v0.1.0. Grafts cannot redefine knowledge history or hide missing old payloads.
Retain explicit shallow-repository and missing-object checks.

Checkpoint messages are nonempty UTF-8, using -m/-F without requiring Conventional
Commits or launching an editor. Feedback identifies the selected Content and new
Checkpoint. Failure may leave unreachable new objects but must not overwrite a
competing reference update. Merge representation is supported by validation;
a general formal-history merge command is outside this batch.

## Explicit discard

For nonempty explicitly resolved target Checkpoints Q contained in K(R), define:

    S_R(Q) = { L in K(R) | some K in Q is a Git ancestor of L }
    K' = K(R) minus S_R(Q)

The ancestor relation includes equality. This is exactly the minimal successor
closure through H union D, including historical external dependencies and merged
formal branches. Do not enlarge S for easier execution. K' is predecessor-closed
when initial R is valid, but it may not be representable by one existing branch
entry per Node.

For each affected Node, point to the unique maximal remaining Checkpoint, or Root
if none remains. Multiple remaining maxima reject the operation. Unaffected tips,
including their Content tails, stay unchanged. v0.1.0 performs no Content-retention
optimization and creates no replacement Checkpoint to make a result representable.
Require the exact final equality K(R') = K'. Old commits are never rewritten.

Provide --dry-run with explicit targets, complete collateral set and reasons,
UUIDs, old/new tips, worktrees, Content losing managed entry, and refusal reasons.
Actual execution must bind explicit authorization to the complete impact, not
merely the input Q. The accepted plan uses a plan summary identifier, interactive
confirmation, and matching-preview authorization for noninteractive execution;
exact option spellings are local interface work.

Affected deployed worktrees must be safe and clean: no staged/unstaged/untracked
changes, unsafe ignored data, or conflicting in-progress Git operation. No
automatic stash, hard reset, clean, forced worktree removal, or user-data loss.
Content is not in S but loss of its managed history entry is a separately reported
destructive effect. Refs, tags, reflogs, and clones may retain objects; do not
manually delete objects, promise restoration, or describe discard as secure erasure.

Validate initial state, compute Q/S/K', check representability, validate complete
candidate refs, preview impact, obtain confirmation, recheck assumptions, execute
a controlled ref transition, and verify actual results. Worktree and ref execution
details need experiments; no cross-worktree filesystem transaction is promised.

## Node deletion and deferred work

Node delete does not cascade into other Nodes. Reject if any other retained
Checkpoint depends on the target Node, including old and non-first-parent formal
history. Its own history and outgoing edges do not alone block deletion.
Require no worktree to have the target branch checked out; no implicit one-Node
undeploy. User may need full undeploy or safe manual checkout changes.
Use explicit destructive confirmation and conditional ref deletion. This removes
managed retention/identity entry, not physical objects or a global UUID tombstone.

The current batch uses standard Git, Haskell, Cabal, and Nix. No patched Git,
CSV, classification registry, independent adopt, partial deploy, historical
multi-Node checkout, automatic formal merge, lost-tip reconstruction, signatures/
trust policy, permanent global dependency index, or cross-clone transactions.
Optional naming strategies and acceleration remain candidates whose inclusion in
0.1.0 is undecided; they do not alter identity or historical semantics.

The initial source was git-roam-design-2026-10-31.org (43390 bytes), member SHA-256
d65ec4e2253e2e2f839780832382d8e0c4cd08923280e6f6df29631ce3b2f953.
Its ZIP identity and the independently executed patch experiment are recorded in
[experiment.md](experiment.md) and the linked immutable experiment archive. That
archive contains only selected local experiment evidence, not the design document.
Those tests do not validate this revised product protocol, Hook, or native
deployment implementation. No new build or experiment result is implied here.
