# Git Roam accepted implementation plan

## Authority, baseline, and boundaries

The user requested implementation of the formal plan on 2026-11-01 after
concluding the design discussion. [design.md](design.md) is the effective product
model; [current.md](current.md) distinguishes actual work from intended features.
This file retains the accepted plan so recovery does not depend on a chat or
ignored temporary file. Node 1 is committed and its exact source was compared
with the verified GHC 9.12 snapshot. Node 2 is implemented and verified in the
project history, confirmed equal to its tested snapshot. Node 3 is implemented and
committed and confirmed against its 28-file tested snapshot. Node 4 is drafted
and awaits separate validation. See current.md for evidence,
actual progress and authorization boundaries.

Use serial milestones, not parallel agents. Each project commit must independently
build and pass its relevant tests/checks. Update README with implemented behavior
and mark roadmap checkboxes only after corresponding verified completion.
The user performs project staging/commits; review and confirm each project commit
before proceeding to the next. No auto-release, tag, or TODO state transition.

## Mandatory pre-project sequence

1. Consolidate GAW current/design/implementation into one coherent current
   knowledge state, including reasons for the adopted revisions. Do not reconstruct
   discarded intermediate proposals or modify the independent experiment archive.
2. Review the entire GAW snapshot, explicitly stage only intended declared
   workspace files, run public GAW check, and create a selective design checkpoint.
   Planning does not automatically justify a latest-HEAD project parent.
3. Only then prepare project commit 0: CHANGELOG.org alone, preserving its
   canonical header and TODO 0.1.0. Add structured user-visible planned features
   under Added with unchecked boxes, not scaffolding/no-op claims.
4. Keep optional naming strategies and deployment acceleration explicitly outside
   the current implementation batch; their eventual 0.1.0 inclusion is undecided.
5. Review the resulting change and relevant checks, provide a commit message,
   and wait for the user's project commit before experiments or milestone 1.

Suggested commit-0 intent: docs(changelog): outline v0.1.0 development goals.
Its entries cover enable/disable; immediate Node worktree creation; native Content
editing and valid history progression; complete-dependency Checkpoints; check/
status; clone/fetch followed by full deployment and missing tracking branches;
full safe undeploy; exact discard with preview; non-cascading Node deletion; and
clear partial-failure/compensation reporting. Keep release state human-controlled.

## Reproducible native Git experiments

Current execution position: node 0 is committed, its root Git-source check passed,
and the standard-Git experiment passed all 66 final cases with unpatched Git
2.56.0 on x86_64-linux. See [native-git-validation.md](native-git-validation.md)
for actual observations, reviewed execution choices and the independent archive.
It covers 31 detailed SHA-1 scenarios per files/reftable backend plus four
SHA-1/SHA-256 object/ref/Hook/worktree smoke cases. Logging/rejection/pair-presence
hooks are fixtures, not the product validator. Git 2.54 and other platforms remain
unverified. The experiment gate is satisfied. Node 1 passed its build, 12 unit and
nine integration cases, and flake check on x86_64-linux. It exposes only help/version,
keeps Git configuration intact in production while isolating test configuration,
uses direct argv/binary stdio and typed Git failures, preserves raw output path
boundaries, and distinguishes SHA-1/SHA-256. Nix selects standard Git at build time.
Tests declare the internal CLI dependency solely in Cabal and find it on PATH.
Following the user's request to match GAW, the overlay selects the GHC 9.12
package set (verified GHC 9.12.3 with bundled Cabal 3.14.2.0). The original
GHC 9.10.3/Cabal 3.12.1.0 reproduced a missing runtime tool despite correctly
building it. No test executable path or separate Setup Cabal override remains;
the earlier workarounds were removed and both suites passed again.
The user separately authorized its formatter and clean-snapshot build/check;
experiment approvals were not reused. The tested clean snapshot includes all
eight new untracked Haskell files; all 20 copied files still match the worktree
and manifest. The user staged and committed node 1, and all 20 committed files
were confirmed equal to that tested snapshot. Node 2 subsequently passed 36
protocol cases, the existing 21 cases, build and flake check under separate
node-2 command authorization. The 48 generated graph fixtures cover both object
formats and distinguish H-only ancestry from combined H/D Git ancestry. Shared
subtrees across Nodes are cached once. The user committed node 2 and its 24
committed source files were confirmed equal to the tested snapshot before node 3.
Refresh snapshots after source changes; approvals remain scoped to their node.

Node 3 now passes all 79 cases (22 native inspection cases plus the existing 57),
build and flake checks on x86_64-linux. check/status share native stored-object
reading and current/candidate managed-state validation, while the pure ordinary
transition relation preserves Root and every old K. Actual Hook enforcement and
controlled creation remain node 4. The user-facing inspection/status CHANGELOG
boxes are complete; repository protection is not. README records scope, codes,
no-repair behavior and unstable-observation limits. The user committed node 3,
and its exact source was confirmed before beginning protection lifecycle work.

After commit 0, use a new isolated directory such as
tmp/git-roam-v0.1.0-native-git/, verifying the temporary boundary before writing.
Do not overwrite the old worktree-batch reproduction. Manage standard Git and
test dependencies with a locked flake. Use dedicated fixture repositories and
local remotes, isolated identity/configuration, and repeatable assertions/logs.
Do not run experimental history/config changes against the project repository.

Validate:
- Clone/fetch with existing, missing, or incomplete local UUID branch sets.
- Native worktree add/tracking creation with one remote, multiple equal tips,
  differing tips, and user default-remote/guessing configuration.
- Named Hook install/coexistence/controlled bypass; actual old refs including
  zero-old input; symbolic HEAD; single and complete multi-ref transactions.
- Expected-old and verify behavior, rejection, supported failure injection.
- Existing checkout, main/linked/detached worktrees, nesting, moving, locks,
  ignored files, partial progress, and safe cleanup.
- Every required feature on the currently pinned standard Git. Git 2.54 is a
  minimum-version candidate, not a compatibility claim, until its matrix passes.

Promote useful experimental assertions to integration tests, and record findings
and their limits promptly in GAW. Evaluate independent raw-evidence preservation
only when warranted; do not treat old archived patch results as product validation.
An experiment may choose a native execution adapter. Reopen requirements only for
a concrete demonstrated conflict between adopted requirements.

## Serial project commits

| Node | Delivered capability and boundary | Principal verification |
| --- | --- | --- |
| 0 | CHANGELOG feature roadmap only | Org structure, preserved header/state, explicit planned status and optional scope |
| 1 | Haskell library, CLI/help/version, injectable native Git runner, fixture helpers, Cabal tests and Nix checks; README build/test instructions | Argument/error boundaries, subprocess errors, common-dir discovery, SHA-1/SHA-256, path/message handling |
| 2 | Permanent protocol and projection, H/D and formal history algorithms | Valid/invalid graphs, multi-predecessor same-UUID history, exact tree/parent roles, empty diff, UUID/Root/dependency conflicts, properties |
| 3 | Shared current/candidate validator; check and status from real objects/refs | Missing branches/versions/objects, retained extra branches, unrelated refs, read-only behavior and indeterminate states |
| 4 | Enable/disable, named realtime Hook, managed coordination and modifying-command prerequisites | Enable on invalid knowledge state and idempotence, install conflicts, other hooks, legal Content/new Checkpoints, refused ordinary create/delete/discard |
| 5 | Internal safe worktree enumeration/planning/primitives, root validation, fixed short names; no public subset-deploy command | Manual/moved/main/detached worktrees, nesting/ignore, collisions/occupancy, lock/user-data safety |
| 6 | Full deploy, canonical remote candidates, missing tracking-branch establishment, complete target closure | Clone then deploy, mutually dependent Nodes, source ambiguity, unchanged existing local tips, incomplete input to complete target, safe compensation |
| 7 | Full undeploy with whole-input safety preflight | All Node linked worktrees, main exclusion/diagnostics, nested order, no start on known unsafe target, partial execution failure, branch/Hook retention |
| 8 | Node create --path creates UUIDv4/Root/branch/worktree and returns UUID/path | Identity/path conflict, author settings, conditional creation, worktree failure and bounded compensation |
| 9 | Checkpoint construction and complete dependency editing | First/repeated Checkpoints, clear/remove/add/replace, new empty Content after Checkpoint, exact committed tree, dirty state preserved, CAS races |
| 10 | Explicit discard --dry-run and complete impact plan | Minimal cross-Node successor closure, old dependencies, merged history, multiple targets/maxima, Content impact, no preview mutation |
| 11 | Confirmed discard execution, conditional refs and safe worktree coordination | Exact remaining formal set, stale/refused confirmation, user-data protection, whole ref plan, post-commit failure classification |
| 12 | Non-cascading Node delete, complete incoming-history scan and checked-out-branch rejection | Historical/non-first-parent incoming edges, own outgoing history, every checkout, expected-old deletion, explicit impact confirmation |
| 13 | End-to-end, compatibility, README tutorial/sync/failure limits and CHANGELOG review | Full multi-Node lifecycle, local-remotes clone/fetch, native progression, discard/delete, full undeploy/disable, executable documentation |

Expose only complete commands actually implemented at each node. Internal single-
worktree helpers do not authorize public partial deployment. Node create must
create its worktree from its first public implementation. Discard initially
exposes only its working dry-run capability; do not advertise execution before
node 11. Every node gets meaningful tests for its contract, not implementation-
mirroring tests or a new no-op placeholder.

## Architecture and data flow

Keep protocol/semantics, Git adapter, validation/planning, application operations,
and CLI separate. Do not extract a GAW shared library. Reuse its separation and
CLI habits without copying its history/message semantics.

Use private constructors for unvalidated snapshots, verified histories, and
verified plans. Read objects/refs into a snapshot, validate current or target
conditions appropriate to the operation, build an explicit plan, then execute
under coordination/conditional updates and inspect actual results.
Typed validation does not freeze Git state after planning.

Git calls pass arguments directly, preserve path/OID boundaries, and do not
assume 40-character hashes. Read true stored history, report incomplete necessary
objects, and do not silently fetch. Cache immutable OIDs within a traversal;
no permanent authoritative global index. Native Git supplies author/committer
configuration; do not invent a user identity on configuration failure.

Check is the shared complete validation entry. Hook provides realtime protection,
with local checks for Content-only changes and sufficient added-history/closure
validation when formal history changes. Per-operation code reuses the validator
instead of invoking a check subprocess or implementing a second interpretation.

## Operation-specific execution defaults

### Lifecycle and candidate selection

All modifying commands except protection lifecycle operations require correctly
enabled protection; check/status remain available without it. Enable does not
demand valid knowledge state. Disable requires no remaining managed Node linked
worktrees and removes only its own protection.

Local canonical UUID branches take priority in deploy and are never advanced.
Discover canonical UUID remote-tracking candidates only for missing local Nodes.
Coalesce equal-OID sources; differing tips require an explicit remote. Do not
allow checkout.defaultRemote or other guessing config to silently choose divergent
history. If native guessing rejects equivalent sources, supply a chosen starting
ref and report it. Exact source-selection option spelling is local CLI work.

Prevalidate the complete final local branch set. Prefer native tracking/worktree
creation when safe. If missing branches require coordinated creation, establish
the jointly validated set in a conditional transaction, then connect tracking and
native worktree operations. Experiments determine the concrete safe adapter.
Do not restore a public adopt command to solve implementation coupling.

### Paths and workspace state

--path is mandatory for node create and deploy; no previous-path registry.
Use canonical UUID ASCII -> SHA-256 -> first 5 raw bytes -> standard Base32 ->
lowercase unpadded, producing 8 characters. Reject collisions without fallback.

Allow ignored subdirectories of main or linked worktrees, never a worktree root.
A first root is absent/empty; reused roots contain only valid Node deployments.
Do not edit ignore config. Respect moved/manual valid linked worktrees at their
actual paths. Deploy rejects a main-worktree Node checkout conflict rather than
moving/switching it; undeploy processes linked targets and reports main specially.
Detached historical worktrees remain outside normal deployment.

Whole-input preflight rejects known unsafe operations before any modification.
For nested removal, use a safe deepest-first order; reject layouts where deleting
a target would touch a non-target worktree or user data. Never force-clean to
satisfy full deployment or removal.

Compensate only newly created unchanged safe state. New branches additionally
require expected-old/no-checkout and a closed compensated ref set. Preserve any
changed or dependency-required branches and report residuals. Deploy may establish
new branches, so rollback cannot be treated as worktree-only.

### Checkpoint, discard, and delete

Checkpoint target selection uses explicit --node or the current legitimate Node
worktree, not a sole-branch guess. Messages use nonempty UTF-8 -m/-F. Start from the
last full dependency map (empty for the first), then clear/remove/add/replace and
validate the final full set; conflicting inputs fail before the ref is advanced.

Root tip requires prior Content. Content tip supplies its committed tree. After a
Checkpoint tip, create a new same-tree Content object and the new Checkpoint, then
advance the final ref once with the original expected-old. No write-tree snapshot,
automatic squash, index inclusion, or reused previous second parent.

Discard takes explicit Checkpoint revisions. Preview computes exact Q/S/K', old
and new tips, causal impact, worktrees and Content loss. Use the fixed unique-max/
Root policy; never optimize Content retention or create a merge to avoid refusal.
Require clean affected worktrees and valid current and final states.

The accepted confirmation default binds authorization to a complete plan summary
identifier: interactive execution previews and confirms the impact; noninteractive
execution supplies the matching preview identifier. Refs or relevant workspace
changes invalidate stale plans. Exact flag names and stable diagnostics are frozen
at the respective CLI node. No force option bypasses semantic validation.

Use a verified native safe update, or temporarily remove only affected clean
linked worktrees, apply the complete ref transaction, and restore original paths,
as experiments establish. Do not touch unrelated worktrees or user data. Ref
commit and filesystem restoration are separately observable outcomes.

Node delete rejects any incoming edge from another retained formal history and
any checkout of the target branch. It neither cascades nor silently undeploys;
preview its own history loss, obtain explicit confirmation and condition deletion.

### Coordination and result classes

Coordinate controlled operations in the common Git directory, compare expected
old values, and verify relevant read-only refs where useful. Only bypass this
operation's own named Hook after independent validation. Prepared phase locks
transaction targets, not all refs. Input zero-old can mean unconstrained update.
Handle no-op, symbolic HEAD and unrelated refs without false Node classification.

Do not promise arbitrary external-process serializability. Current-state check,
candidate validation, local safety and realtime protection are distinct. Report:
- pre-commit refusal;
- confirmed protocol/closure violation;
- inability to stably observe a state;
- Git read/execution failure;
- refs committed but a later verification/worktree step failed.
Postcheck is not rollback or a perpetual guarantee. Never claim all succeeded
after partial execution or silently perform destructive recovery.

## Tests, compatibility, and documentation gates

Cabal tests and flake checks cover pure examples/properties plus real isolated Git
fixtures. Include both files/reftable, SHA-1/SHA-256, real named hooks, local remotes,
spaces/special path characters, native Content changes, cross-Node ancestry traps,
and controlled fault injection. Use fresh fixtures rather than project refs.
Do not claim archived no-checkout benchmarks validate actual checkout or this DAG.

Retain x86_64-linux, aarch64-linux, and aarch64-darwin. Record tested versus
unavailable platforms. Minimum Git 2.54 remains a candidate until the entire
required feature/behavior matrix passes. Do not add a second legacy protection
system or integrate patched Git as a shortcut.

For each node, run the relevant tests plus package/flake checks after command
authorization. Intended root commands are:
- timeout 120s nix fmt --no-write-lock-file (only when formatting is needed)
- timeout 120s nix build --no-link --no-write-lock-file -L path:.#default
- timeout 120s nix flake check --no-write-lock-file -L path:.

Commands may download and write Nix store/cache/logs/artifacts; fmt changes files.
Respect active authorization, timeout and escalation rules; do not automatically
increase a timed-out command. Old experiment approvals do not cover this task.
Adding dependencies uses the locked nixpkgs foundation and minimal required
changes; do not update locks without the applicable authorization.

Node-0 validation: fmt and the path:. package build passed. The raw path:. treefmt
check invoked copied GAW configuration without git-gaw and failed. The separately
authorized Git-source . check passed against the clean committed roadmap, reusing
available results. Do not repeat raw root path:. checks or disable live protection.
Git-source . includes tracked worktree edits; untracked modules need an explicit
clean source snapshot or user staging. A snapshot can copy the intended project
files under ignored tmp/ without .git, .agents or unrelated data, and be checked
as a standalone path flake. This does not authorize staging project files.

The [Nix flake reference manual](https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html)
documents local Git-source selection and inclusion of tracked worktree changes.
That Git-source retry has now succeeded in this repository on x86_64-linux.

README always describes that node's actual implementation, preserving the user's
authorship and Org conventions. CHANGELOG stays TODO 0.1.0; use headlines and
checkboxes for planned user capabilities, not internal scaffolding. No state,
CLOSED, release, tag, or publication changes are implied by completed boxes.
Do not write final staged commit messages from unrelated unstaged implementation;
inspect the eventual staged diff for an evidence-based message.

At acceptance, execute the documented lifecycle on multiple Nodes and a second
local clone: enable; create/worktree; native Content; precise dependency versions;
Checkpoint; fetch/deploy/tracking; native FF; preview/confirm discard; safe delete;
full undeploy; disable. Report actual platform/compatibility gaps. Complete README
and checkbox review without declaring a release.

## Memory and evidence continuity

Maintain current findings, reasons, actual checks, blockers and next action as
work proceeds. Checkpoint selectively at consequential design, experiment, and
handoff states, not mechanically for each project commit. Select project parents
only for exact snapshots actually supplying relevant provenance; uncommitted
states or future target commits do not become guessed parents.

The optional naming/acceleration decision comes only after the standard Git loop.
The old independent experiment and its archive remain evidence with their original
scope; no old approval, benchmark, or imported claim authorizes or verifies new work.
