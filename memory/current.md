# Git Roam current state

## Current handoff: B3 session correction implemented and verified

The user committed initial B3 at fd3a694561dbbf8bc1ab527ba9d1e58b56bbd741.
All 60 committed blobs matched the successful B3 snapshot at correction entry;
the transition checkpoint grounds that exact committed state. The requested B3
correction is now complete in 12 uncommitted project paths, including new shared
test/BatchFixture.hs. The project index is empty. The agent did not stage/commit/
push ordinary project files. Await user review/commit; B4–B6 were not implemented.

BatchOutcome separates a callback result from completion problems. Typed
BatchRequestFailed and BatchProcessExited allow retaining prior complete,
validated responses; BatchCompletionUncertain invalidates all metadata evidence.
Startup returns BatchNotStarted without a callback value. Unknown cleanup,
stdout/stderr drain/handle errors, shutdown timeouts, escaped outstanding readers
and unexpected trailing stdout remain conservative. A poisoned request is
recorded even if the callback handles its failure; further requests cannot enter
the stream. Original exchange framing/OID/size/terminator checks, masking,
callback exception propagation, cancellation, process-group termination,
independent cleanup worker and reader scope boundaries remain intact.

withGitBatchObservation exposes that outcome through existing adapters and
preserved decorators. withGitBatch is the real strict policy: callback completion
plus zero session problems, otherwise Left. withHistorySource still uses it;
no changes to protocol decoder, candidate rules or management architecture.
CommitObservation contains observedCommits plus commitSessionProblems. Its map
covers every unique requested OID, including failures. Classified later failures
preserve verified metadata, while uncertain completion replaces all OID results
with unavailable errors. Empty requests start no child; OIDs still deduplicate
and normal native queries share one scoped batch process. No second transport.

Status aggregates one commit_session_incomplete diagnostic per query with
property=commit and no invented Node; object failures retain commit_unavailable
with Node/property. All-successful objects plus process exit failure still exit
3. tip/worktrees/remote and ref change detection remain independent. The symbolic
Node branch diagnostic is now Node-level (property omitted); symbolic tip/commit
stay unavailable without reading through that alias. The live CLI uses the
extracted pure statusResponse mapping; tests verify native query reports use
complete JSON/CBOR, shared diagnostics, empty machine stderr and text errors.
No new top-level fields, CLI options, normal schema, metadata/subject semantics,
protocol or B4 working-tree property. README Version status and failure policy
are corrected; CHANGELOG remains TODO v0.3.0; package metadata stays 0.2.0.

Final authorized 300s/single-job/core nix flake check passed (exit 0): fresh
-Wall -Werror build, all 16 suites / 358 groups, treefmt 59 eligible files with
zero changes. Status has 52 groups and Batch 38: 16 groups added overall. Native
commit/Status/strict-reader regressions cover SHA-1/SHA-256 x files/reftable.
Lifecycle tests exercise actual self-executable scoped children, successful
prefix plus truncated/invalid OID/size/terminator responses, poisoning, nonzero
exit, unexpected trailing stdout, startup, exceptions/cancellation, reader escape,
request/process counts, object-map completeness and default no-object costs.
Native strict tests prove callback reads succeed but withHistorySource, Inspect
and validateCandidate reject failed final sessions. Two old ignored-request
expectations were strengthened from Right to Left, never relaxed.
Final derivation:
/nix/store/y9mlwm097frwhqfmsm5j60lfrffg333s-git-roam-0.2.0.drv.
Only x86_64-linux checked; other systems/minimum Git/10^4-Node timing not proven.
Two initial checks passed formatting but stopped at -Werror (variable shadowing/
unused binding, then a test helper shadow); these were fixed. The third check
passed all tests; no test failure or timeout occurred in this correction.

All 61 final worktree files match tmp/b3-session-verification.json and the tested
isolated tmp/b3-session-check snapshot by SHA-256; original B3 evidence remains.
The complete 12-path diff, including the new fixture, was reviewed and diff HEAD
--check passed. One coherent fix: split not necessary, high lifecycle/safety
coupling. Full-diff tmp/commit.md uses
fix(GitRoam.Git.Batch): preserve verified commit observations,
without a Breaking footer. Source/tests and durable findings suffice; no new raw
archive or additional project parent for this uncommitted fix. If user commits,
verify blobs against the session manifest before grounding its exact state.
Do not repeat unchanged tests merely to obtain a parent. B4 is next under a new
instruction. Standing full-Haskell-scope/full-diff draft convention applies only
to this conversation/current Status redesign, with no project Git-write authority.

## Initial B3 completion evidence (before the active correction)

Status now accepts exact -p commit selection. Default remains tip/worktrees/remote.
CommitMetadata contains full tree OID, ordered direct parents, separate author/
committer byte names/emails and dates, subject and unchanged message. CommitDate
uses Integer Unix seconds plus original signed four-digit offset; there is no
ISO rendering or timezone inference. Name/email/subject/message use Output.Bytes
(JSON utf8/base64, CBOR bytes). No mailmap or encoding-header conversion occurs.
Subject is the first LF-delimited message line with one terminal CR removed;
the original message, including nonstandard newlines/NUL/non-UTF-8, is unchanged.

GitRoam.Git.Commit is an independent metadata decoder/reader. It groups multiline
headers correctly, ignores opaque extension/signature data, rejects malformed or
repeated required headers, checks object type and reads only selected tips.
readStoredObject was extracted from Git.Objects and reused without changing the
protocol decoder's metadata obligations. One native scoped cat-file process is
shared by tip reads and equal OIDs are deduplicated. Defaults/tip-only launch no
cat-file, and metadata never traverses parents, validates history or scans files.
Missing ancestors do not block reliable tip metadata. Missing/wrong/malformed
tip objects produce commit_unavailable with Node/property context, retain other
properties/Nodes, and yield complete partial JSON/CBOR with exit 3. Symbolic Node
branches remain diagnosed/unavailable even if their resolved OID was read for
another ordinary Node. Existing before/after ref change detection is preserved.

Output.Number now carries Integer and uses CBOR.encodeInteger, avoiding platform
Int narrowing of timestamps. Existing checkpoint-count values convert from Int
without changing their wire values. CLI help, README and CHANGELOG TODO v0.3.0
reflect the implemented property. Package/release metadata remains 0.2.0; no
release-state/time changes, new dependency versions or lockfile changes.

Final authorized 300s/one-job/one-core nix flake check completed with exit 0:
fresh -Wall -Werror build, all 16 suites / 342 groups (Status 44, 14 added), and
treefmt on 58 eligible files with zero changes. New native groups cover SHA-1/
SHA-256 x files/reftable, Root/Content/multi-parent tips, non-UTF-8 messages with
encoding headers, opaque signature continuations, different identities/dates,
mailmap independence, all three CLI formats, exact output keys, partial errors,
missing ancestors, strict history rejection, costs, races, shared OIDs and
symbolic aliases. Unit groups cover byte identity/message preservation, empty/
nonstandard messages, malformed headers/dates, signed/unbounded integer dates,
missing/wrong objects, transport/process/framing errors and empty reads.
Final product derivation:
/nix/store/lmn59x5nbzmpz5dsqrp86gvhpyylp4mh-git-roam-0.2.0.drv.
Only x86_64-linux was checked; other platforms/minimum Git/10^4-Node timings
are not proven. No timeout occurred. The initial full check passed formatting,
compilation and 15 suites but four new tests mis-modeled Inspect's direct
HistoryFailure as an error inside a report. Corrected only the assertions and
added output/dedup/symbolic coverage; the final check passes all suites.

All 60 final worktree files match tmp/b3-verification.json and the checked
isolated tmp/b3-check snapshot by SHA-256. Original B2 manifests are preserved.
The complete 11-path diff, including untracked new modules, was reviewed;
diff HEAD --check passed. The phase is one coherent change; split not necessary,
medium complexity. tmp/commit.md contains the complete-diff draft:
feat(GitRoam.Application.Status): add tip commit metadata queries.
No Breaking footer is needed for this additive property. Source/tests and durable
findings suffice; no new raw archive or uncommitted project-parent association.

See [status-stage-b.md](status-stage-b.md) for the B1–B7 contract and evidence.
B4 remains working-tree status; keep worktrees/status independent properties
linked by raw path. B5 must atomically migrate management reportManagedState
consumers and Hook ref enumeration. Partial observations never establish trusted
ManagedState. Check scope, protocol and management safety were not changed.

Only for this conversation/current Status redesign B1–B7, draft a commit message
from the COMPLETE stage diff at phase completion, using the principal full
Haskell module name as scope and validated tmp/commit.md. This is not a global
preference or project Git-write authorization. Working-directory Nix eval/build/
check and outside-workspace read-only commands are authorized. B3 also has scoped
Haskell/Cabal formatting authorization using local treefmt with a 120s bound;
checks retain 300s/one-job/one-core limits. No project commits/pushes or lifecycle
changes. If the user commits B3, verify blobs against the final manifest before
grounding that exact state; do not rerun unchanged tests solely for a parent.
Earlier handoff sections below are historical rather than current next actions.

## Completed follow-ups: creation format cleanup and output documentation

The user identified that CreateNode still carried an always-TextFormat argument
after removal of local CLI --format, and that Output's module comment still
described creation only. The previously committed feature worktree was clean.
The cleanup simplifies CreateNode to FilePath plus optional NodeId, removes the
unused createArgs format accumulator and localFormat rendering fallback, update
six parser assertions, and describe Output as the shared CLI output layer.
Only Cli.hs, Output.hs and test/Creation.hs change; no new user-facing behavior
is intended. The existing authorized 300s one-job/one-core isolated flake check
completed with exit 0: fresh compilation, all 14 suites / 286 test groups and
treefmt (51 eligible files, zero changes) passed. Successful derivation:
/nix/store/gprcwzygm4h569y43231mlgbfklydyb1-git-roam-0.2.0.drv.
Only x86_64-linux was checked; other declared platforms were omitted. No timeout
or failed attempt occurred for this follow-up. All 53 current source files match
the checked snapshot by SHA-256; the temporary manifest is recorded separately
as tmp/create-format-cleanup-verification.json so the earlier committed feature's
manifest remains intact. The user committed all three files as refactor(cli):
remove redundant creation format state. All 53 blobs of that committed snapshot
match the verified manifest. The prior cleanup checkpoint had no project parent
because its tested changes were then uncommitted.

The user subsequently committed docs(cli): align structured output documentation.
Its complete two-file diff was reviewed: README limits the four-field map to
creation, replaces stale text-only stderr claims with a link to the shared output
section, and distinguishes deployment/undeployment node/path pairs from nested
inspection/deletion path/main pairs. The Hook comment now describes both ignored
global prefix pairs. Runtime code is unchanged by this documentation commit.
Static diff --check passed; tests were not rerun for docs/comments. Historical
release notes and the old v0.2.0 handoff were deliberately left as versioned facts.
The project worktree and index are clean. The new checkpoint associates the final
reviewed committed handoff; the full test evidence belongs to its byte-confirmed
cleanup parent, with the documentation-only difference explicitly recorded here.
Both follow-ups are complete. Await the next user objective; do not rerun unchanged
checks or initiate release work automatically.

## Completed implementation: unified top-level output format

The unified CLI output implementation is complete and committed by the user as
feat(cli): unify structured output with a top-level format option. The project
worktree and index are clean. Only top-level --format text|json|cbor is accepted; node create's local
option is removed and treated as ordinary invalid arguments. Default text, exit
codes, history protocol, safety and interaction are preserved. Help stays text;
version supports all formats. Hook dispatch ignores complete global option pairs
independently of public validation. No node list or persistent setting was added.

Output centralizes the byte-aware Value model, shared JSON/CBOR codecs, report
mappings and legacy text renderers. JSON stdout is one LF-terminated value;
CBOR has no trailing newline. Existing creation fields and authoritative JSON
Base64/native CBOR path bytes are preserved; raw ref/config bytes share that
encoding. Report diagnostics/warnings are in stdout, preserving nonzero status
for invalid history/blocked previews. Without a report, stdout is empty and
noninteractive machine stderr uses JSON Lines for both formats. Human terminal
delete previews/prompts remain text outside that protocol; automation uses
--dry-run/--confirm. Parameter failures retain exit 2.

Shared Diagnostic values are attached directly to application failures, using
operation-level codes plus typed inspection categories without parsing English.
Evidence captures known removals, remaining worktrees/refs/config, candidate
OIDs, attempted actions and ref-update confirmation. Unknown observations use
null; confirmation does not assert post-compensation state. Bundled failure
pattern synonyms retain the two-argument source interface and legacy reason/
details text. README, help and unreleased CHANGELOG document the interface and
breaking local-format removal. Version metadata/released history are unchanged.
The commit contains all 18 reviewed files, including the new Diagnostic.hs module.
The agent did not stage or commit project files.

The user authorized targeted Haskell formatting and on-demand checks, one Nix
job/core, 300s checks and 120s formatting. The isolated 53-file source at
tmp/unified-format-check includes the new module without index changes. First
check stopped at Cabal ordering; second compiled and passed 13/14 suites, with
two Unit assertions still using removed syntax. Those were migrated. The third
check freshly compiled and passed all 14 suites / 286 test groups. Treefmt
checked 51 eligible files with zero changes. No timeout was observed.
Successful derivation:
/nix/store/kxvbirzykc8ax1cd1qnm4xchbj6r5l45-git-roam-0.2.0.drv.
Only x86_64-linux was verified; aarch64-linux/aarch64-darwin were omitted.

All 53 committed source files were compared against the verified SHA-256 manifest
and matched exactly, including docs, Cabal metadata and the new module. This
grounds the existing successful check in the committed feature without rerunning
unchanged tests. The manifest at tmp/unified-format-verification.json is temporary
verification material, not a required archive. Final diff --check passed. Coverage
includes JSON/CBOR framing/model parity, arbitrary path bytes, format conflicts,
both ref backends/object formats, empty/multiple Nodes, warnings, invalid-history
reports, deletion execution, actual Hook wrappers and enhanced existing partial-
failure injection tests. No raw archive is needed. The previous implementation
checkpoint had no project parent because the tested source was uncommitted.
The new committed-source handoff associates the now byte-confirmed feature
snapshot; its only new ancestor is the reviewed feature on the retained baseline.
This task is complete. Await the next user objective; do not rerun unchanged
checks or initiate version bumps, releases or node list work automatically.

## Completed issue 2: pack-refs loose pruning

The user committed the issue 1 fix as fix(undeploy): allow residual REBASE_HEAD
during removal, then requested implementation of issue 2. The project worktree
was clean. The repair preserves transaction old OIDs and allows a zero-new-OID
Node row only for the files backend when its nonzero old OID matches the actual
ref, loose file and unique packed entry, with no packed-refs.lock before/after
reading. Real files-backend deletions hold that lock through prepared, including
their nested packed transaction; nested old OIDs may also be zero. Git upstream
2.54.0 and 2.56.0 sources confirm that distinction. The candidate logical ref is
retained; other updates still undergo existing candidate validation. Unreadable
evidence and unsupported backends refuse deletion.

Two new Protection groups cover evidence failures and mixed transactions on both
object formats. Four new EndToEnd groups use the installed Hook, both ref
backends/formats, linked-worktree pack-refs with and without pruning, repeated
packing, native Content commit plus maintenance pack-refs, preserved refs/reflogs/
Hook config, and genuine deletion rejection for loose-only, duplicate and
packed-only refs (update-ref with/without expected OID, branch -D, and single/multi
stdin transactions). README protection prose and unreleased CHANGELOG are updated.
The user authorized one 300s flake check with max-jobs=1/cores=1. The approved
outside-sandbox run passed treefmt (50 files, zero changes) but failed production
compilation under -Werror=name-shadowing: local values shadowed the existing
configuration helper. Renamed it to packedValues within the authorized repair
scope. No test suite ran. Failed derivation:
/nix/store/qb1j5mz4jz22kw1p613qg7hfjhkshbpv-git-roam-0.2.0.drv.
The user subsequently authorized on-demand testing within this task. Repeating
the same exact flake check command with the same limits is authorized until this
repair is verified; do not broaden commands or run unchanged checks after passing.
The second run completed with exit 0 within the limit. Fresh compilation and all
14 suites / 280 test groups passed, including the six new regression groups.
Treefmt processed 50 files with zero changes. Successful product derivation:
/nix/store/b5qj44c7p218hnvkmi72pqsqf4r0gdbb-git-roam-0.2.0.drv.
Only x86_64-linux was checked; aarch64-linux and aarch64-darwin were omitted.
Final diff --check passed. The user committed the five intended source/test/
documentation files as fix(protection): allow pruning redundant loose Node refs.
The latest project commit has the reviewed five-file scope and the project
worktree/index are clean. Both reported issues are implemented, verified and
committed in separate commits. The agent did not stage or commit project files.
Await the next user objective; do not rerun unchanged checks or reproduce the
reported incident repository. No version bump or release action is implied.

For the completion handoff, both committed repair diffs were reviewed against
the inherited completed-feature baseline. They contain only the seven reviewed
source/test/documentation paths and agree with the staged changes previously
reviewed in this session. The project-parent association grounds this final
committed-source review; the test executions described above preceded the
user's commits and were not rerun solely for checkpoint provenance. This is one
completion checkpoint for the combined resolved objective, not reconstructed
intermediate checkpoints or a claim that memory was checkpointed earlier.

## Completed issue 1: residual REBASE_HEAD removal preflight

The user reported two maintenance-related false refusals and requested source
review, then authorized implementing issue 1 first as a separate change. Do not
reproduce their incident repository. The source worktree was clean before this
change. Worktree.removable now omits REBASE_HEAD as an independent blocker while
retaining rebase-merge/rebase-apply and all other existing checks. New
Undeployment regression groups cover files/reftable and SHA-1/SHA-256: each
state directory blocks all removal both with and without REBASE_HEAD, then a
residual REBASE_HEAD containing a reachable OID allows removal while refs and
Hook configuration remain unchanged. The user committed the source, tests and
documentation together before starting issue 2.
The user authorized one 300s flake check with max-jobs=1 and cores=1. The initial
sandbox attempt could not open Nix's fetcher cache; the approved outside-sandbox
run completed with exit 0, without timeout. Fresh compilation and all 14 suites /
274 test groups passed, including all four new regression groups. Treefmt
processed 50 files with zero changes. Product derivation:
/nix/store/5ww6lvjzccrl09b5zdnlhzbnnbvjk05s-git-roam-0.2.0.drv.
Only x86_64-linux was checked; aarch64-linux and aarch64-darwin were omitted.
The issue 1 repair is implemented, verified and committed.
At the user's subsequent request, README.org's Full undeployment section and
CHANGELOG.org's existing unreleased entry now document this fix and the retained
state-directory safety checks. Released entries and version metadata are unchanged.
These documentation-only additions passed static diff review and diff --check;
the earlier flake check predates them and was not rerun.
The later successful issue 2 flake check includes these committed changes and
documents; its current results are recorded above.

## Completed feature and production baseline

Completed post-v0.2.0 task: implement top-level --deploy-path as the first Added
item in the user's existing TODO *unreleased* entry, and update README. Preserve
that human-created heading and the v0.2.0 release history. The adopted public
contract is prefix-only, absolute path, no repetition, and mutual exclusion
with subcommand --path even for equal values. node create/deploy require one
path source; their local --path keeps invocation-relative behavior. Other
public commands/help/version accept the prefix without filesystem inspection.
No deployment environment variable, remembered root or history protocol change.

The user clarified that --deploy-path must not affect --reference-transaction.
Internal Hook dispatch is therefore independent of public path validation:
wrapper-supplied prefix pairs are ignored before entering the unchanged Hook,
without validating their values. Hook configuration, stdin, phases and safety
checks are unchanged; no bypass is authorized. This lets a PATH wrapper prepend
the option for all invocations without making protection depend on a directory.

Implementation and documentation are complete, verified and committed by the
user as feat(cli): add top-level deployment path option. The project worktree
and index are clean. The commit contains six files: CHANGELOG.org, README.org,
Cli.hs, Unit.hs, EndToEnd.hs and git-roam.cabal. The first Added entry describes
the option; README supplies wrapper examples and the Hook boundary. The package
remains 0.2.0; this unreleased feature is not in the v0.2.0 tag.

Six new unit groups and four end-to-end wrapper groups cover SHA-1/SHA-256 with
files/reftable. Real PATH wrappers exercise native valid Content commits and
invalid updates through the installed Hook. Direct Hook tests use relative
unused deployment values: those values do not replace transaction validation.
Other public commands accept unused absolute paths without filesystem checks.

The first build compiled production code but exposed a missing explicit filepath
dependency in the unit-tests component; it was added and the clean source snapshot
refreshed. The second fresh build passed all 14 suites / 270 test groups with
-Wall -Werror. Product derivation:
/nix/store/gajlshxxzhi00qiwn4xaqgfjd5jw72sl-git-roam-0.2.0.drv.
The authorized build used a 300s timeout and command-local max-jobs=1/cores=1;
there was no timeout. The final 120s flake check reused that product and freshly
checked formatting (52 traversed, 50 eligible, zero changes). Only x86_64-linux
was tested; aarch64-linux and aarch64-darwin were omitted, not verified.

Temporary source identity and logs are in tmp/top-level-deploy-path/. After the
user's commit, all 52 committed files were compared by SHA-256 with the verified
manifest and matched exactly. This associates the recorded 14-suite / 270-group
build and flake-check evidence with the committed feature without rerunning
unchanged tests. The feature commit adds only the six previously reviewed files
on top of the finalized release; its ancestor history is already retained as
baseline context. The new project-parent association grounds the completed
feature handoff in that exact source, rather than merely following main HEAD.
The frozen v0.2.0 changelog, detailed notes and README Deferred candidates are
unchanged. No separate archive is needed for routine feature checks.

This feature task is complete; await the next user objective. No version bump,
release-state transition or new tag is implied. Do not repeat completed tests,
modify the v0.2.0 release tag or initiate platform-publication verification.

v0.2.0 is locally finalized and tagged. The user committed
build(v0.2.0): finalize release metadata as 3e6e283, after the release-guide commit
3b6d0b2. The project was clean at that release handoff; the subsequently committed feature
is described above. The committed Cabal version and
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
and memory handoff is complete; the post-release objective is recorded above. Do not initiate
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
