# Stage B: Status queries and protocol validation

## Source, scope and assessment

Adopted user development guide plus supplementary judgment, received on
2026-11-12 Asia/Shanghai. This is an English distillation, not verbatim source;
selected original evidence is linked from current.md. Supplied baseline:
ren-lingyu/git-roam main, 17c2594c6423c899b39d99bdcb01431efc2e9eb9. Current HEAD
matched during read-only assessment. Future phases inspect actual latest HEAD.
Target: current unreleased line; Root/Content/Checkpoint protocol is unchanged.
Only assessment, memory/archive and checkpoint work is authorized in this task.
Do not execute the guide's builds, commits or pushes as implicit authorization.

Retain seven independently buildable/testable/reviewable development nodes.
B5 must migrate all relevant callers together, rather than leave a new
intermediate abstraction. Fixed product/protocol decisions are constraints;
recommended module/type names may use equivalent designs. Technical assumptions
remain unverified until tests establish them.

The seven boundaries are coherent at the inspected baseline: B1 shared reads,
B2–B4 observation, B5 complete validation migration, B6 Check convergence and
B7 acceptance. B5 is the highest safety risk: inventory callers and implicit
preconditions before coding. B3/B4 byte parsers and B6 tri-state evidence need
focused review. This assessment is not exhaustive implementation validation.

## Verified repository facts

Cli's shared inspect helper dispatches both Status/Check through inferNode,
inspectState and inspectionValue. Inspect mixes discovery, refs, protocol/
connectivity checks, worktree registration and presentation. Create, Undeploy,
Delete and Checkpoint use InspectionReport.reportManagedState. Deploy imports
Inspect.validateCandidate; Protection validates transaction old/new candidates
through it. B5 inventory therefore includes report consumers AND direct
candidate-validation consumers, not just searches for reportManagedState.

Inspect reads refs before/after, rejects shallow repositories and selected
symbolic branches, validates history/connectivity, then reads worktree
registration. Removing presentation must not silently drop safety-relevant
read failures/ref consistency. Deploy has batch local/remote reads and its own
strict policy; Worktree also has strict reads/removal preflight. Deploy.remoteNode
uses refs/remotes/ with a nonempty slash-terminated prefix and final canonical
UUID. That prefix does not itself prove a configured remote name.
Git.Worktrees already retains path/head/branch/main/bare/detached and optional
lock/prune reasons; reuse its porcelain -z parser. Objects.decodeCommit only
extracts tree/parents, not presentation metadata. requireProtection requires
exact singleton expected event/command/enabled values in BOTH repository-local
and effective config; matching config does not prove runtime Hook availability.

Evidence: targeted reads of Cli.hs, Output.hs, Application/{Inspect,Deploy,
Protection}.hs and Git/{Objects,Worktrees}.hs, plus caller/preflight searches
including Application.Worktree. No test or benchmark executed. The user credits
Git official for-each-ref/worktree/status/cat-file interfaces; the trailing
“git-for-each-ref Documentation+3” is an unresolved citation marker, not verified
source links. No official-page contents were supplied or checked here.

## Public Status decisions

Keep global prefix-only --format text|json|cbor, no -f/subcommand --format.
Require exactly one -t/--type repo|node; even identical repetition is invalid.
Repo rejects -n/-p. Node accepts repeated single-value -n/--node <uuid> and
-p/--property <property>, deduplicated as sets. Sort Nodes by UUID and properties
by a fixed implementation order independent of argument order. No current/all
selectors. No -n means ALL canonical local refs/heads/<uuid>, excluding remote-only
Nodes. Missing explicitly selected Nodes yield diagnostics/nonzero while
preserving other successes.

-p is exact selection. Default is tip, worktrees, remote. node UUID is always
present; internal dependencies never add output keys. Five properties:

- tip: full object-format-aware OID, no commit parse. Preserve symbolic-ref
  evidence and diagnose anomalies rather than presenting them as ordinary refs.
- worktrees: Git-registered Node checkouts, reuse existing porcelain -z parser.
  Recommended path/head/branch/main/bare/detached/locked/lock_reason/prunable/
  prune_reason; raw absolute path bytes, full refs/OIDs. [] means no worktrees.
  Registration does not imply accessible paths; no safe_to_undeploy inference.
- remote: locally stored upstream {remote,source,ref} or null plus refs array
  of full {ref,tip}. Allow remote='.' and upstream outside refs/remotes/. Keep
  confirmed config when resolved refs are missing; ambiguous upstream needs
  diagnostics. Reuse Deploy's Node candidate rule without inferring arbitrary
  prefixes are real remote names. No network/fetch, push prediction/refspec/URL,
  ahead/behind/divergence or redundant same_tip. Empty refs is successful [].
- commit: tip-only commit metadata, tree/full ordered direct parent OIDs,
  author/committer name/email/date, subject and entire unchanged message.
  Date = integer Unix seconds + original +/-HHMM offset; no IANA/extra ISO
  inference, mailmap or signature verification. Names/email/message use raw
  bytes and Output.Bytes (JSON utf8/base64; CBOR bytes). No extra raw field
  required. Separate metadata parser from protocol decoding; historical
  validation must not be forced to parse extra presentation metadata.
- status: per-worktree path, state clean|dirty|unavailable and nullable
  staged/unstaged/untracked/unmerged flags. Any true is dirty; reliable all-false
  is clean; failures never become clean. Recommended native command:
  git --no-optional-locks status --porcelain=v2 -z --untracked-files=normal
  --no-ahead-behind. Correctly parse ordinary, rename/copy extra path, unmerged,
  untracked and submodule records with NUL boundaries and arbitrary path bytes.
  Ignored files do not count. clean is not deletion safety, absence of ongoing
  operations/user data or protocol validity.

Adopted supplement: worktrees and status remain TWO INDEPENDENT properties,
linked by raw worktree path. Selecting status may internally read registration
but must not add/reshape worktrees output. Shared selection reuses one observation.

Repo reports only repository.protection.state + diagnostics:
enabled|disabled|misconfigured|unavailable. Enabled agrees with requireProtection;
distinguish local/effective/inherited, missing, duplicates/conflicts and failures.
No Node/history/worktree scans, counts/deploy root or runtime Hook guarantees.

## Validation and mutation boundaries

Check becomes protocol-only: Node/identity, Root/Content/Checkpoint structures
and parent order, contexts, necessary objects/types, tree structure/names,
connectivity, shallow evidence and relevant ref changes. Current Protocol
modules/tests define the rules. Public report does not browse worktrees/dirty/
protection/delete safety/sync, although necessary internal evidence reads remain.
Preserve existing Check scope: explicit --node, otherwise current canonical
Node inference, otherwise whole local set. This differs from Status's all-Nodes
default. Do not unify them for cosmetic consistency.

Recommended report: valid true|false|null, checked_nodes [{node,tip}], diagnostics.
True = complete pass; false = definite violation; null = incomplete without a
definite violation. Keep both violations and unknown evidence; never success
when either prevents it. checked_nodes means refs actually selected, not all
context commits read. Stable diagnostic codes and existing exit/error categories
survive; justified changes require explicit tests/rationale.

Extract direct complete-state load and explicit candidate-ref validation APIs
returning trusted ManagedState only on complete success. Mutators depend on
these, not Status/Check CLI reports or partial observations. Retain protocol,
shallow/connectivity/identity, expected refs, operation locks, worktree preflight,
transaction protection, execution-time rechecks, compensation and residual
reporting. Audit implicit Inspect worktree reads and replace necessary safety
premises explicitly. No permanent old/new adapter or compatibility wrapper.

## Models, partial reports, performance and read-only behavior

Use domain types independent from Output.Value; typed NodeProperty and explicit
all/selected Nodes and default/explicit properties are recommended. Output maps
reports to text/JSON/CBOR; CLI parses/dispatches. Deterministic map-based ordering.

Repo root has repository/diagnostics; Node root has nodes/diagnostics. Unrequested
property omitted; requested empty uses valid []/null; requested failed is null
plus diagnostic. Local failures preserve successes and mark failed items.
Status unknown flags are null. Diagnostic code/severity/message stays stable;
recommended Status context {node,property,path} avoids parsing natural language.
Dirty/disabled/successfully observed locked/prunable states exit 0; incomplete
reads nonzero; bad arguments 2. Keep Check failure categories.

JSON stdout = one complete value + LF; CBOR = one complete value without LF.
UUID/OID text; raw fields JSON utf8/base64 or CBOR bytes. No report => empty
stdout; machine stderr JSON Lines diagnostics. Partial reports remain complete
valid values. Clarify report/stderr diagnostic routing against existing output
conventions during implementation, not by accidental duplication/loss.

No global Status transaction lock or strict atomic-snapshot promise. Batch refs,
query selected properties, recheck relevant refs when needed; diagnose detected
changes. Worktree statuses describe individual observation times. Never use a
Status cache as mutation authority. No ref/worktree writes, maintenance, repairs,
fetch/push/resets or persistent cache. Suppress optional index locks; sanitize
Git redirection environment and preserve filesystem path bytes.

Target <=10^4 Nodes. Default must not traverse history, read each tip commit,
scan each worktree or launch Git linearly with Node count. Batch refs/worktree
registration; remote shares refs, commit may batch object reads; status scales
with worktrees/files. No daemon/watcher/cache or speculative complex concurrency.

## B1–B7 phase gates

1. B1: shared batch local/remote ref facts and errors with refname/OID/symref,
   correct object format, Deploy candidate identification and reused worktrees.
   Adapt Inspect/Deploy/Worktree without CLI changes or loosening caller policy.
   Test UUID filtering, symbolic refs, malformed output, order/duplicates,
   remote recognition and format/backend combinations with existing consumers.
2. B2: typed Status queries/reports, -t/-n/-p, repo protection, tip/worktrees/
   remote, defaults/exact selection, text/JSON/CBOR and partial diagnostics.
   Bare status becomes invalid here; Check remains unchanged. Test parser
   repetitions/mixed options/rejections, missing Nodes, all-Nodes default,
   config states, multiple/undeployed Nodes/worktrees, upstream/remote refs,
   bytes and protocol-invalid history still observable.
3. B3: standalone tip metadata reader with type checks and property diagnostics.
   Test root/single/multiple parents, distinct identities, timestamp boundaries/
   offsets, empty/nonstandard/multipart messages, non-UTF-8/encoding and header
   continuations. Define/test subject extraction. tip does not read commits;
   commit does not traverse ancestors or invoke protocol validation.
4. B4: porcelain v2 status parser/per-worktree summaries, submodules/NUL/rename
   records, clean/dirty/unavailable and partial failures. Cover staged/unstaged/
   untracked/unmerged, special/non-UTF-8 paths, locked/prunable/missing paths,
   no associated worktree, selected Nodes and no index/ref/user-data changes.
5. B5: migrate ALL reportManagedState consumers AND candidate validators in one
   coherent node. Audit implicit worktree preconditions. Preserve Create,
   Deploy, Undeploy, Delete, Checkpoint and Protection Hook safety. Invalid/
   missing history, races, invalid config, dirty/ignored/untracked user data,
   compensation/residual evidence and multi-Node contexts remain protected.
6. B6: independent protocol-only Check/report, preserved scope/inference,
   tri-state validity and typed diagnostics. Remove old InspectionReport,
   status-history presentation and wrappers after last real callers migrate.
   Cover protocol/tree/context/missing/shallow/race/scope failures.
7. B7: full integration/review and README/help/CHANGELOG aligned with implemented
   behavior. Document required -t, new Status selection/default/schema, Check
   validation schema and removal of primary history/worktree browsing, and
   top-level long --format. Audit schemas/codes/exits, duplicate readers, obsolete
   APIs, performance/read-only and both object formats/backends. Design examples
   must not be documented as already implemented.

Each node: builds, all existing and appropriate new tests pass under
-Wall -Werror, malformed parser-input tests, explained behavior changes, no
skipped failures, no protocol/data-safety regression, independently reviewable
and committable. Keep necessary cross-module migration together. Suggested
checks: cd cabal; cabal test all, and root nix flake check; actual environment
and explicit execution authorization control. NONE ran in this assessment.

Test layers: unit CLI/selection/parser/time/model/encoding, native Git integration
and real CLI/installed-Hook end-to-end. Relevant phase end-to-end matrix:
SHA-1/SHA-256 x files/reftable; tiny unit tests need not all repeat four times.
Key regressions: invalid protocol still yields tip/worktrees; one unavailable
worktree preserves other results and complete machine stdout/nonzero exit;
Git adapter traces prove cost isolation (tip no cat-file history, remote/default
no status, status no protocol validation, commit no ancestor traversal);
mutators never consume partial Status as trusted state.

## Remaining decisions and completion

Subject derivation, submodule summary, malformed metadata behavior, missing/
ambiguous upstream representation, ref-race evidence, protection classification
and exact diagnostics/schema details need implementation tests/review. The plan
is accepted, not a claim these technical assumptions are established facts.

Completion requires independent Status/Check/mutator layers, reusable Git reads,
complete trusted mutation validation, all five Node properties and repo
protection, stable byte-safe partial reports, cost/read-only tests, all safety
regressions passing and no permanent obsolete internal compatibility code.

Excluded: node list/status, editor/Magit/TUI/plans, batch management, refresh,
auto fetch/push/live network, ahead/behind/divergence, full history browser/diff,
notes/signature validation, generic refspec engine, new cache/DB or protocol
changes. Do not reopen historical experiments/releases as implicit work.

Next: await explicit B1 implementation instruction; inspect latest HEAD and
preserve the existing CHANGELOG edit, map callers/failure policies and identify
authorized paths/check commands before beginning implementation.
