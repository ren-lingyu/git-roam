# Git Roam implementation boundaries

## Status and reading order

Use [design.md](design.md) for current effective product constraints and
[current.md](current.md) for actual repository state and validation. This file
defines the intended v0.1.0 scope, implementation guidance, and open decisions.
It is not an existing CLI/API reference, an implementation completion claim,
or authorization to execute commands. No product behavior below is implemented
by the present no-op executable.

## Required v0.1.0 loop

The intended first version must allow users to:

- Create a UUID Node with a valid Root and active local branch.
- Deploy and undeploy its worktree; validate/admit compatible fetched history
  when the corresponding local active branch does not exist.
- Edit, stage, commit, and revise unconfirmed Content with native Git.
- Create a Checkpoint from committed Content, inheriting the prior dependency
  set by default and changing multiple dependencies in one validated operation.
- Protect formal history through the Hook while permitting legal Content-tail
  changes; prevent uncontrolled structural updates.
- Explicitly check Node/repository history using the shared validator.
- Delete an unreferenced Node safely, considering every retained historical
  Checkpoint and associated worktrees.
- Batch deployment through a basic manifest with whole-input preflight,
  user-file protection, and actionable failure reporting.

This loop must work independently of advanced Org integrations and optional
patched Git. Signatures, deployment configuration languages, or global caches
must not become prerequisites for the core history protocol.

## Implementation guidance, not a frozen API

Continue with Haskell, native Git CLI, and Cabal/Nix. Reuse the separation of
responsibilities demonstrated by GAW without extracting a shared package yet:

| Responsibility | Intended contents |
| --- | --- |
| Protocol | Root/Content/Checkpoint data and parent/tree, identity, dependency, continuity, and anchor rules |
| Validation | Read Git-derived data into validated history states; memoize immutable commits during a traversal |
| Git adapter | Native object/ref access, cat-file, commit-tree, conditional update-ref, and worktree operations |
| Application | Creation, checkpointing, checking, deletion, admission/deployment, structural lock, and failure handling |
| Hook/CLI adapters | Decode external requests/ref transactions, share validation, and explain failures |

Module names and type signatures are not chosen. Types may distinguish validated
commit roles, but constructors or parent counts alone cannot prove actual Git
objects valid. CLI, Hook, and explicit checker must use the same invariants.

Creation/checkpoint/check/deploy/undeploy/delete/status are intended capabilities;
the document's `git roam ...` spellings and options are suggestions, not a
published contract. There is no planned `git roam commit` wrapper for ordinary
editing. Do not add unsupported command examples to user-facing documentation.

### Deployment candidate

The current proposed batch input is CSV with `uuid,directory` columns, where
directory is a parent deployment directory, not an arbitrary full worktree path.
For canonical UUID text `u`, the proposed short name is the first 40 bits of
SHA-256, encoded as eight lowercase unpadded base32 characters:

```text
<directory>/<short(u)>/<uuid>/<payload files>
```

The worktree root is `<directory>/<short(u)>`; its checked-out Git tree already
contains the UUID directory. The UUID remains the identity, and short-name
collisions must be detected/rejected rather than silently lengthened away.
The exact hashed bytes and CSV syntax are not frozen; this is a deployment
candidate, not a permanent Node protocol requirement. No fixed note filename
or mandatory classification directories follow from this example.

Optional external Nix/scripts can generate a manifest. Git Roam need not parse
a fixed `main` structure or introduce a permanent deployment language.

### Decisions still required during implementation

Resolve these deliberately before exposing the affected public behavior:

- Exact command names/options, input diagnostics, Git configuration handling,
  and author/committer defaults.
- CSV header/escaping rules and canonical UUID bytes for hashing; lowercase
  hyphenated UUID ASCII is a candidate, not a newly adopted encoding rule.
- Hook installation/removal conflicts and named-hook configuration/feature
  compatibility. The planned mechanism follows GAW's reference-transaction
  approach; a supported Git version contract is not established by the local
  2.54.0/2.56.0 worktree experiments.
- OS mutex implementation, acquisition/error behavior, and release on termination;
  worktree compensation, partial-failure reporting, and interrupted-state recovery.
- The user interface for any active-branch rename, without changing historical
  Node identity.
- Whether operations add stricter marker blob/mode protection beyond the
  permanent regular-file/path rule.

Do not settle these implicitly while reorganizing memory, present them as
implemented, or change parent/tree semantics to make an implementation easier.

## Required verification scenarios

These are planned acceptance scenarios, not an existing or passed product test
suite:

| Area | Required coverage |
| --- | --- |
| Root/Content | Root has no parents and only the UUID marker; reject wrong path/type and subtree escape; allow nonempty historical marker and empty Content diff; retain identity |
| Checkpoint | First Checkpoint requires non-Root Content; exact tree equality; zero-new-Content reuse and chains of different lengths; reject unrelated forks |
| Dependencies | Reject non-Checkpoint/self targets and duplicate UUIDs; allow explicit older versions, arbitrary external-parent order, and different indirect versions; test inherited mapping and batch add/remove/replace |
| Failure boundaries | Invalid final dependencies do not advance refs; dirty staged/unstaged/untracked state is preserved and excluded from checkpoint content |
| Hook/native Git | Allow legal commit/amend/reset/rebase and valid fast-forward outcomes; reject lost anchors, native multi-parent commits, and direct Checkpoint rewrite/deletion; cover actual refs, symbolic HEAD, no-op, non-FF, malformed and indeterminate states |
| Concurrency | Content vs Checkpoint CAS race; independent Content edits; dependency creation vs deletion under the common structural lock; termination releases lock |
| Deletion | Scan older historical dependencies, not only current tips; permit unreferenced Nodes with their own Checkpoints/outgoing edges; protect occupied worktrees and user files |
| Admission/deployment | Fetch followed by validated admission; reject same UUID/different Root and incompatible histories; duplicate UUIDs, path escape/conflicts, short-name collision, interruption/recovery, and files/reftable backends |
| Scale | Separate native and optionally patched Git measurements; source calls for 100/1000/5000/10000 worktree coverage, without claiming this complete matrix has run |

The independent worktree experiment is evidence for local registration behavior,
not evidence that these product scenarios pass. Protocol/plumbing validation
and real-file checkout measurements remain separate.

## Evidence and packaging direction

Use [experiment.md](experiment.md) and its stable archive reference for the
locally executed worktree reproduction. Both source-pinned Git 2.54.0 and
nixpkgs-provided Git 2.56.0 were exercised there, including no-checkout
registration through 5000 worktrees and defined injected failures.

The user prefers eventual packaging by appending patches to a nixpkgs Git
derivation, retaining its source/version/build choices rather than introducing
an independently fetched Git source. This preference was demonstrated in the
isolated experiment; it has not been integrated into the application flake.
Patched Git remains optional acceleration, not a core protocol dependency.

The supplied document's earlier commit-tree comparison (reported 12/12),
GPG/signing, SIGTERM and historical performance claims were not independently
rerun as part of that worktree reproduction. Keep those as source statements
where relevant, not passed local tests. Its statement that the worktree flake
was unbuilt describes the source author's context; current local evidence is
the separately maintained experiment record. No fresh external-source or
Git Hook compatibility verification is claimed by this memory update.

## Outside v0.1.0

Do not expand the first version to include a globally coordinated unique-ID
allocator, permanent UUID tombstones/retirement, enforced signatures or trust/
permission policy, cross-clone transactions, automatic merge/conflict repair,
historical multi-Node checkout or dependency-version materialization, a central
authoritative knowledge snapshot/index, required Nix/Org content, advanced
Org-roam-organize navigation, fine-grained multi-ref concurrency optimization,
or productionizing/upstreaming the Git batch patch.

Future signing must distinguish generating and validating signatures; it is
not a current requirement. Derived indexes can remain disposable and must not
supplant Git history. Refine the relevant open decisions in a separately scoped
implementation plan before coding; this document does not invent missing
interfaces or an approved implementation schedule.
