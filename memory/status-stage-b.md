# Stage B: Status queries and protocol validation

## Current B6 override

The latest user B6 plan supersedes the initial Check-scope rules below: Check
always validates the whole set exposed by native enumeration, removes --node and
inference, uses independent Valid/Invalid/Inconclusive reports (true/false/null,
exit 0/1/3) and optional initial --show-refs MAP. Preserve initial refs across
later errors and make ref/session integrity override provisional violations.
Unify static Validation, distinguish malformed reliable objects from read failure,
remove Inspect and keep operation preflight/Hook strict acceptance. Checkpoint
still uses inferNode. Check reads no worktree/status/upstream/protection data.

The user CANCELLED raw Git enumeration / patched dependency: dangling symbolic
refs silently omitted by Git 2.56.0 are a documented detection boundary, not a
v0.3.0 ref-backend implementation task. Protocol requires direct valid Node refs
regardless of detection limits. Existing visible symbolic refs still reject.
Audit and protect concrete Create/Deploy UUID name occupancy using native refs
exists and no-deref creation, without redesigning the ref observation model.
Current implementation/check progress is in current.md. Do not follow stale
historical instructions to preserve Check --node or solve raw enumeration first.

## Source, scope and assessment

Adopted user development guide plus supplementary judgment, received on
2026-11-12 Asia/Shanghai. This is an English distillation, not verbatim source;
selected original evidence is linked from current.md. Supplied baseline:
ren-lingyu/git-roam main, 17c2594c6423c899b39d99bdcb01431efc2e9eb9. Current HEAD
matched during read-only assessment. Future phases inspect actual latest HEAD.
Target: current unreleased line; Root/Content/Checkpoint protocol is unchanged.
Initial authorization covered assessment and memory/archive/checkpoint only.
The user authorized B1 and subsequently B2 implementation, synchronized docs
(TODO v0.3.0), on-demand working-directory Nix eval/build/check, outside-workspace
read-only diagnostics and B2 scoped Haskell/Cabal formatting.
The guide itself does not authorize project commits or pushes.

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

Initial planning evidence: targeted reads of Cli.hs, Output.hs, Application/{Inspect,Deploy,
Protection}.hs and Git/{Objects,Worktrees}.hs, plus caller/preflight searches
including Application.Worktree. No test or benchmark ran in that initial assessment. The user credits
Git official for-each-ref/worktree/status/cat-file interfaces; the trailing
“git-for-each-ref Documentation+3” is an unresolved citation marker, not verified
source links. No official-page contents were supplied or checked during that initial assessment.

## B1 implementation and completed verification

Canonical Node ref identity uses Protocol.Identity.parseNodeId: arbitrary
canonical lowercase hyphenated UUID text, not only v4/Nil/Max. Creation has a
separate stricter ID policy. B1 must preserve non-v4 canonical refs; a mistaken
new test expectation was corrected rather than changing production behavior.

The shared reader preserves full names, object-format OIDs, symbolic targets
and remote path prefixes; one for-each-ref call handles each requested scope.
Callers retain strict symbolic/error policies and existing validation/preflight.
Duplicate relevant rows now fail closed rather than Map.fromList losing evidence;
this concerns malformed adapter output, not valid native ref enumeration.
Worktree porcelain continues to use the existing parser without duplication.

Implemented paths: new cabal/src/GitRoam/Git/Refs.hs and cabal/test/Refs.hs,
consumer migration in Application/{Inspect,Deploy,Worktree}.hs, Cabal module/
Refs-suite registration, README and root CHANGELOG. CLI/Output/Protocol are
unchanged. Worktree registration reuses existing Git.Worktrees; no second
porcelain parser or permanent compatibility API was introduced. README records
only B1 as implemented and distinguishes planned later Status behavior. The
user's existing TODO v0.3.0 title is retained; released history/package metadata
is unchanged.

Verification used an isolated 55-file snapshot in tmp/b1-check including both
untracked new files, without project staging. Authorized command:
`timeout 300s nix flake check path:/home/lingyu/Projects/git-roam/tmp/b1-check --no-update-lock-file --max-jobs 1 --cores 1 --print-build-logs`.
The initial sandbox attempt could not connect to the daemon. First outside-
sandbox check stopped at one Deploy formatting difference. The next passed
formatting but compilation found an accidentally removed forM import used by
compensation (failed product derivation crwkbpzanrx12c3041mc38hqxwpkp7mb).
Restoring it enabled fresh compilation; the following check passed all 14 old
suites and eight new native groups but the new identity unit wrongly rejected
canonical UUIDv1 (failed product derivation vr7x85yc36zk1i9jza1pp0bxdp5viyp7).
The test was corrected to assert acceptance, preserving production semantics.

Final check returned exit 0 within 300s, no timeout: fresh compilation with
-Wall -Werror; 15 suites / 298 groups pass, including 12 new Refs groups.
Treefmt processed 53 eligible files, zero changes. Successful product derivation:
/nix/store/crskxfnnm8lwpzjx5kwflyikxhw3zvjd-git-roam-0.2.0.drv.
Verified system x86_64-linux only; aarch64-linux/aarch64-darwin were omitted.
All 55 current source/document files match the successful snapshot's SHA-256
manifest; static diff --check passed. The manifest remains temporary material
at tmp/b1-check-manifest.json, not necessary raw archival evidence.

Coverage includes canonical/non-v4/Nil/Max identity, ordinary branch filtering,
byte-safe remote-prefix/symbolic evidence, order/duplicate and malformed/OID
failures, one-call batching with invocation/error/warning preservation, native
SHA-1/SHA-256 x files/reftable refs and shared worktree observations, plus all
three callers' strict symbolic handling. Existing selected Inspect still accepts
an unrelated symbolic Node; whole-set Inspect and Worktree/Deploy refuse it,
even when its OID matches the trusted snapshot. Deploy also still refuses
symbolic remote candidates for existing local Nodes. No paths are created by
these refused operation scenarios. Existing lifecycle/Hook/race suites pass.
This does not establish all-platform, exact-minimum-Git or 10^4-Node benchmark
claims. No benchmark was run. The first implementation-completion checkpoint retained the then-uncommitted
verification state without a project parent. The user has since committed B1
with full module scope GitRoam.Git.Refs; all 55 committed blobs match the verified
manifest and the project worktree/index are clean. The committed-source handoff
associates that exact project state without rerunning unchanged tests. Recoverable source/tests and durable results
suffice; routine failed/successful build logs need no new archive.

## Initial B2 implementation and verification (before review corrections)

The user committed the initial B2 implementation as a2018485275e476c9cb9645cb2dc67c27b40b482.
All 57 committed blobs matched the original checked snapshot. This section
retains pre-review implementation evidence; corrections are recorded below.
Its implementation baseline was the user's B1 commit. Changed project paths: Application/{Status,Protection,Inspect,Deploy,
Worktree}.hs, Git/Refs.hs, Cli.hs, Output.hs, git-roam.cabal; tests Status/Refs/
Unit/Output/Inspection/EndToEnd; README.org and CHANGELOG.org (17 paths total,
including two new files). Package/release metadata and Protocol modules are
unchanged. The TODO development target stays v0.3.0.

RefObservation is the foundation result, carrying reliable typed records and
errors. observationComplete derives from errors; requireCompleteRefs is the
strict policy gate used by Inspect/Deploy/Worktree. Decode retains independent
valid rows, quarantines every duplicate including valid/malformed conflicts,
and marks incomplete/truncated observations. Exit-success warnings preserve
reliable rows but fail completeness; transport/nonzero process stdout is not
salvaged without a reliability guarantee. This fulfills the post-B1 B2 model
requirement rather than wrapping the old strict reader with Status.

LocalAndRemoteUpstreams extends batch ref atoms with Git's resolved upstream.
One batch branch remote/merge config read preserves original/missing/duplicate
config independently of the resolved ref. Official for-each-ref and config
references were consulted for this implementation:
https://git-scm.com/docs/git-for-each-ref and https://git-scm.com/docs/git-config.
Native tests establish the used upstream behavior. Status accepts local remote='.',
keeps configured missing-target evidence, and diagnoses ambiguity. No per-Node
Git calls. Default before/after ref reads, batch config and worktree registration
have identical subprocess counts at 2 and 34 Nodes in every format/backend.

Application.Status separates typed query/property/Node/remote/report/diagnostic
models from Output.Value. PropertyResult distinguishes NotRequested,
Unavailable and Available, including known absent upstream versus failed config.
Remote refs distinguish unknown from known-empty and retain known partial refs.
CLI requires a single -t repo|node; -n/-p repeat as sets, UUID order is stable,
properties are exact/default tip/worktrees/remote, and missing selected Nodes
have diagnostics while successes survive. Repo rejects selectors and observes
only protection, using shared local/effective reads and actual requireProtection
requirements. Config warning/read failures are unavailable and strict checks
reject them; no runtime executable availability is asserted.

Text/JSON/CBOR outputs are independent from the old inspection display. Raw
paths, branch/ref/config/identity-related bytes use Output.Bytes. Node UUID/OID
stay text. Omitted vs empty vs unavailable properties are distinct; partial
machine reports include contextual diagnostics in stdout, exit 3 and remain
complete values. Before-report failures keep empty stdout and stderr JSON Lines;
argument errors exit 2. Check retains its previous scope/validation/report at
B2. It still uses InspectionReport; B5/B6 work is not silently claimed done.
Commit and worktree status properties are rejected until B3/B4 implement them.

Added 16 Status test groups: parser and exact selection; partial/duplicate/
truncated/warning evidence plus strict consumers; protection config states;
byte-safe JSON/CBOR; native batch upstream/local '.'/missing/ambiguous config,
remote-only exclusion and multiple ref paths; invalid protocol still observable;
partial property/config failures, ref races and CLI complete partial reports.
Native integration/CLI groups cover SHA-1/SHA-256 x files/reftable. Adapter traces
prove no cat-file/history/status/fetch calls in defaults and exact tip costs.
Existing public workflow tests were migrated for the intentional Status break;
existing management/Hook/safety/protocol tests pass.

The first check passed formatting but failed new production list head under
-Werror=x-partial (derivation 2xi8l9mrwb7kw6vjbqdj44rqqq5x6yqi); byte-boundary
parsing/patterns fixed it. The next fresh build passed 16 suites / 314 groups
(derivation hx37ciw8inkzyxcydpgxlha3nj5540bz). Review then strengthened unavailable
upstream modeling, text presentation, config warning handling, multi-remote tests
and the 2-to-34-Node call-count regression. The final fresh code build/check
passed all 16 suites / 314 groups under -Wall -Werror:
/nix/store/0r192cnaqkms3rpx13lmf1sj5j9g5wix-git-roam-0.2.0.drv.
All checks used 300s, max-jobs=1, cores=1; no timeout occurred. Only x86_64-linux
was verified, other declared systems omitted. A formatter tree-root flag
conflict was corrected before formatting; scoped formatting then passed.

After removing an obsolete B1 no-CLI-change sentence from root CHANGELOG, final
flake check reused the identical Cabal product and freshly passed treefmt on
55 eligible files, zero changes. All 57 final source/document files match the
isolated checked snapshot at tmp/b2-check; SHA-256 manifest is temporary
verification material, tmp/b2-check-manifest.json. Static diff --check passed.
No new raw archive or guessed project parent for uncommitted code is needed.

The entire phase diff, including new files, is reviewed as one coherent B2
change. Draft tmp/commit.md uses full module scope GitRoam.Application.Status
and a BREAKING-CHANGE footer. The subsequent user commit was verified by blob
equivalence without rerunning unchanged tests. The later B2 review, corrections
and current next action supersede the original handoff.

## B2 review corrections: implemented, verified, staged by the user

The user supplied a review of committed initial B2, identifying three groups:
upstream config semantics, failure coupling/partial config loss, and remote
candidate scope/empty-result semantics. Static code inspection confirmed them.
The report's independent Git 2.47.3 experiments were attributed source evidence,
not our test results. Native regressions now confirm the relevant behavior on
this project's pinned Git 2.56.0. This is one B2 repair, not B3/B4/B5/B6 work.

Changed paths (seven): Application/Status.hs, Git/Refs.hs, test/Status.hs, new
test/StatusRegression.hs, git-roam.cabal, README.org and CHANGELOG.org. Public
parameters, default properties, output fields, protocol, check scope and strict
readNodeRefs/requireCompleteRefs guarantees remain the same. No refspec engine,
new Status public fields or compatibility wrapper was added.

Upstream semantics now distinguish known absent merge configuration from an
unresolved configured upstream. Remote-only config is a successful upstream:null
observation, including default status -t node. Native upstream:remotename
supplies Git's effective remote when resolved; config records retain read order
for last-value scalar evidence if native resolution is unavailable. Repeated/
inherited remote entries are not treated as ambiguity. merge remains multi-valued;
multiple entries retain known remote information and diagnose the single-upstream
representation limit. Missing remote/mapping retains known merge evidence and
an unresolved diagnosis. Official references consulted:
https://git-scm.com/docs/git-config and https://git-scm.com/docs/git-for-each-ref.

UpstreamConfigObservation replaces all-or-nothing config parsing. Native
NUL-terminated key-only entries (no LF/value) produce Node-local problems;
other Nodes' successful config remains available. Unknown record framing,
transport or nonzero command failures remain global/unavailable. Config semantic
problems are filtered to selected Nodes; global read failures are not hidden.

Normal Status paths still combine ref/upstream atoms. On upstream command or
transport failure, Status explicitly falls back to LocalAndRemoteNodes batch
observation, keeps independent base facts and preserves the original upstream
failure diagnostic/nonzero exit. Failed stdout is still discarded by readNodeRefs;
strict consumers still require complete base evidence. Both before/after passes
apply this policy. Base fingerprints always compare refs/OIDs/symbolic targets;
metadata fingerprints are compared only when observations are comparable.
There is no atomic multi-batch snapshot claim or per-Node subprocess fallback.

Symbolic remote semantic diagnostics now apply only to chosen local Node IDs.
Unselected local and remote-only symbolic candidates do not cause semantic
failure. Global ref errors/warnings still invalidate completeness. refs:null
means selected candidates existed but no ordinary candidates can be reliably
reported; refs:[] means genuinely none. Mixed candidates retain ordinary refs
plus the selected Node diagnostic. Deploy's strict rejection is unchanged.

Added 14 regression groups (Status now 30 groups). Native four-combination
fixtures test no config, remote-only default success, normal/local upstream,
repeated remotes, global/local precedence, multiple merges, unresolved merge,
valueless config/fallback, independent tip/worktree/tracking data, retained A
config despite B's bad entry, complete JSON/CBOR partial reports/exit 3,
selected/unselected/remote-only symbolic cases, nullable refs, global warnings
and Deploy refusal. Explicit default JSON and CBOR CLI assertions cover
remote-only and repeated remote successes; JSON asserts symbolic-only refs:null.
Adapter tests exercise command failure with unreliable stdout, bounded four-ref
fallback calls, base-read failure with no fabricated Nodes, strict protocol/
worktree rejection and races during fallback. Existing normal-path 2/34-Node
call-count regressions still pass with two ref queries, one batch config read
and one worktree registration query.

Both authorized full nix flake check runs completed successfully within 300s,
max-jobs=1, cores=1, without timeout. Initial successful product derivation:
/nix/store/j5d1gicqnfnlvsxiynn7jdxxnagi6qry-git-roam-0.2.0.drv.
After adding explicit final CLI assertions, the final fresh build/check passed
all 16 suites / 328 groups with -Wall -Werror and treefmt on 56 eligible files,
zero changes. Final derivation:
/nix/store/yny4andfmm9x3xn480hcj30rs80x6c0w-git-roam-0.2.0.drv.
One new test layout parse error was fixed before building; no production compile
or test failure occurred in the correction runs. Only x86_64-linux was checked;
other systems, exact minimum Git/Git 2.47.3 and 10^4-Node timings are not proven.

All 58 worktree AND index files match the final snapshot by SHA-256. Temporary
verification material is tmp/b2-review-check and tmp/b2-review-verification.json;
do not overwrite the original initial-B2 manifest. The user staged changes
during execution and then staged the final test assertions; no agent project
staging was performed. The complete seven-path diff is reviewed as one coherent
fix. Static diff HEAD --check passed. Draft tmp/commit.md uses
fix(GitRoam.Application.Status): preserve scoped upstream observations,
without a Breaking footer. At completion the fixes were staged/uncommitted;
that checkpoint correctly added no guessed project parent.
Source/tests plus durable conclusions suffice; no raw review archive is needed.

The user committed these corrections at 693f478fca5a680de8aa188ae66280772a0d738c;
all 58 committed blobs match the reviewed verification manifest and the project
worktree/index are clean. B2 is frozen; the user explicitly requested B3.

## Initial B3 implementation and verification (before session correction)

Baseline is the user's committed B2 correction, verified by 58-file equivalence
before B3. B3 is implemented and verified but uncommitted; the project index is
empty and the agent did not stage or commit ordinary project files. Eleven paths
changed: new Git/Commit.hs and test/CommitProperty.hs, Application/Status.hs,
Git/Objects.hs, Cli.hs, Output.hs, git-roam.cabal, test/Status.hs, test/Output.hs,
README.org and CHANGELOG.org. No B4–B6 implementation, protocol changes, lockfile,
package version or release-state/time changes are included.

The independent CommitMetadata/CommitIdentity/CommitDate types preserve raw
name/email/message bytes, ordered parent OIDs, tree OID, Integer Unix seconds
and raw signed HHMM offset. Subject takes the first LF-delimited message line
and removes one terminal CR from that line; message is byte-for-byte unchanged.
No mailmap or declared-encoding transcoding, signing verification or timezone
inference occurs. Header continuations attach to their preceding header, so
opaque signature/mergetag continuation rows cannot masquerade as metadata.
Missing/repeated required headers and malformed identity/date fields fail the
property. Integer timestamps avoid platform overflow; Output.Number/CBOR now
support integers directly, with an explicit conversion for old Int counts.

readStoredObject was extracted from the existing raw object loader and reused;
protocol decodeCommit still reads only tree/parents. Commit metadata type checks
raw objects and shares one scoped cat-file batch with unique selected tip OIDs.
Only -p commit starts this reader; exact selection does not leak tip or other
fields. No parent/tree traversal, protocol validation, file scan or per-Node
native child process. Missing ancestors are allowed for observation. Partial
failures yield commit:null with commit_unavailable Node/property diagnostics;
successful properties/Nodes survive. Symbolic aliases cannot acquire an available
metadata result merely because another ordinary Node has the same resolved OID.
Before/after reference change diagnostics remain intact.

CLI parser/help and text/JSON/CBOR mappings are updated; raw fields use the
existing utf8/base64 versus native bytes contract. README documents metadata,
subject/date/byte rules, exact selection and costs. CHANGELOG adds the feature
under TODO v0.3.0. Official Git cat-file/commit-tree documentation was consulted:
https://git-scm.com/docs/git-cat-file and https://git-scm.com/docs/git-commit-tree.

Added 14 test groups (Status now 44), covering malformed headers/date/envelopes,
empty/multiple/nonstandard message lines, byte identities/messages, encoding and
signature headers, signed/large timestamps with lossless JSON/CBOR, empty reads,
wrong/missing objects, process/transport errors, native Root/Content/multi-parent
metadata, mailmap independence, text/JSON/CBOR CLI, exact keys, retained partial
results, no ancestor reads, unchanged default/tip costs, strict history refusal,
ref races, equal-tip deduplication and symbolic aliases. Native groups run across
SHA-1/SHA-256 x files/reftable. All production components compile -Wall -Werror.

The first full check passed formatting and 15 suites, but four new strict-refusal
assertions expected an InspectionReport when missing ancestors instead return
HistoryFailure directly. Corrected those assertions without altering production
validation, and added output/dedup/symbolic checks. The final authorized 300s
single-job/core nix flake check passed all 16 suites / 342 groups, treefmt on 58
eligible files with zero changes, no timeout. Final derivation:
/nix/store/lmn59x5nbzmpz5dsqrp86gvhpyylp4mh-git-roam-0.2.0.drv.
Only x86_64-linux was checked; other systems/minimum Git/10^4-Node performance
are unverified. All 60 final worktree files match the tested tmp/b3-check snapshot
and tmp/b3-verification.json by SHA-256; the index is empty. Static diff HEAD
--check passes. The initial failed snapshot manifest is retained separately.

The complete eleven-path diff, including both new modules, is one reviewed B3
feature; split not necessary, medium complexity. tmp/commit.md uses full module
scope GitRoam.Application.Status and no Breaking footer for the additive property.
No new raw archive is warranted, and no uncommitted code is used as an additional
project parent. Await user review/commit; verify its blobs before grounding the
exact committed state. Proceed to B4 only under a new instruction.

## Completed B3 correction: session completion and object evidence

Baseline is fd3a694561dbbf8bc1ab527ba9d1e58b56bbd741, whose 60 committed blobs
match the original successful B3 snapshot. The correction is verified but
uncommitted in 12 paths: Git.hs, Git/{Batch,Commit}.hs, Application/Status.hs,
Cli.hs, tests Batch/CommitProperty/Status.hs, new test/BatchFixture.hs,
git-roam.cabal, README.org and CHANGELOG.org. Project index is empty; no agent
ordinary project staging/commit/push. B4–B6, protocol, subject/date parsing,
normal CLI/schema and default properties are unchanged.

Shared BatchOutcome now carries callback evidence independently of typed session
problems. Request failures and nonzero child exits preserve prior verified
responses for observation. Uncertain cleanup (including extra trailing stdout,
drain/handle failures, timeout, escaped outstanding reader or cleanup exception)
invalidates metadata. No callback value is fabricated for startup failure and
callback exceptions propagate rather than becoming partial success. A poisoned
request is recorded even if the callback handles its failure; subsequent reader
requests fail before touching the process. Existing masking, independent cleanup
worker, cancellation, process termination and raw OID/size/body/terminator
validation are retained. Strict withGitBatch rejects any session problem and
withHistorySource remains strict. Two old ignored-request tests now require Left
rather than Right; this is a stricter boundary, not weakened expectations.

CommitObservation has a complete requested-OID map plus separate session
problems. All unique requested OIDs have Right metadata or explicit Left errors.
Empty input starts no process; equal OIDs share reads; one native scoped child
serves normal commit queries. Uncertain outcomes revoke all metadata, while
classified later failures preserve prior responses. Status emits one global
commit_session_incomplete with property=commit, retains Node-level
commit_unavailable for object errors, keeps tip/worktrees/remote and ref change
checks, and exits 3 even when every object property succeeded. No extra top-level
schema fields. symbolic_node_branch now has Node context without an unrequested
tip property; symbolic tip/commit remain unavailable. The extracted pure
statusResponse is used by the live CLI and fault-report encoding tests.

Shared native self-executable BatchFixture preserves old fake child scenarios,
adds controlled later-request/exit/trailing-output faults and delegates ordinary
Git reads to the pinned executable. Both test suites declare it; new file is in
the Nix snapshot. Native commit fixtures exercise three OIDs with a middle missing
object, truncated/wrong-OID/size/terminator responses, a first-response process
exit, all-successful objects then exit 7, and extra trailing stdout. They assert
complete keys, prefix retention/revocation, deduplication and one child. Native
Status reports retain real worktree registrations/tracking refs/tips, structured
session versus object contexts, complete JSON/CBOR, empty machine stderr, text
errors and unchanged default cost. withHistorySource callback success is observed
before final failure; withHistorySource, Inspect and validateCandidate all reject
the bad session. These fixtures cover SHA-1/SHA-256 x files/reftable. Additional
transport tests cover startup, completion, prefix/poisoning for both OID lengths,
exception propagation, cancellation/reaping and reader scope; old repeated-
cancellation/outstanding-reader/cleanup/framing tests stay in place.

README now describes implemented B3 in Version status and the exact conservative
failure policy. CHANGELOG adds the fix under TODO v0.3.0 without release state,
time, version or lockfile mutations. The final authorized 300s/one-job/core nix
flake check passes all 16 suites / 358 groups (Status 52, Batch 38, 16 added),
-Wall -Werror and treefmt on 59 eligible files with zero changes. Derivation:
/nix/store/y9mlwm097frwhqfmsm5j60lfrffg333s-git-roam-0.2.0.drv.
Only x86_64-linux checked; other platforms/minimum Git/10^4-Node timings unknown.
Two initial formatting checks passed but builds stopped at new -Werror warnings;
fixed shadowing/unused binding/test helper naming. Third check passes all tests;
no timeout or test failure. All 61 worktree files match the checked isolated
snapshot by SHA-256: tmp/b3-session-check and tmp/b3-session-verification.json.
Original B3 manifests are preserved. Full diff reviewed, diff HEAD --check passes.

One coupled fix; split not necessary, high lifecycle/safety coupling. Draft
full-diff tmp/commit.md uses GitRoam.Git.Batch scope and no Breaking footer. No new
raw archive or uncommitted project parent needed. Await user review/commit; verify
its blobs before grounding. The user has now committed this correction at
b7a0e150547c51a46fed3a01413344f6dadd2e41, verified by 61-file equivalence.
The explicitly requested B4 work is recorded below.

## Completed B4: verified native worktree status

Baseline is the user's B3 correction commit, verified by 61-file equivalence.
B4 is implemented/tested but uncommitted in nine paths: new Git/Status.hs and
test/WorkingTreeStatus.hs, Application/Status.hs, Cli.hs, Output.hs,
git-roam.cabal, test/Status.hs, README.org and CHANGELOG.org. Index is empty;
no agent ordinary project staging/commit/push. Package stays 0.2.0, development
TODO v0.3.0, no release-state/time/lock/protocol or B5/B6 changes.

NodeProperty adds StatusProperty; NodeStatus carries separate per-worktree
status observations. Worktrees/status share one registration observation but
exact selection never leaks dependency fields. Worktree records sort by raw
path and only selected Nodes are scanned. No associated worktrees => [], failed
registration => status:null. Per-path unavailable => state=unavailable and all
four boolean flags null plus worktree_status_unavailable Node/property/path
diagnostic. Other successful properties/Nodes survive; dirty exits 0 and read/
partial failures exit 3. Defaults remain tip/worktrees/remote without scans.
Text, JSON and CBOR keep existing byte encoding and report-completeness rules.

The Git.Status parser consumes porcelain-v2 -z record structure, including two
NUL paths for rename/copy, ordinary tracked fields, unmerged, submodule flags,
byte filenames and unknown optional headers. Malformed/truncated/empty records,
mode/OID/XY/score errors fail the worktree. A lone NUL is invalid, not clean.
Unmerged XY is conflict-side state and sets unmerged separately; normal XY
sets staged/unstaged. Submodule HEAD/content dirt contributes unstaged; U also
untracked, with fixed ignore-submodules=none despite ignore config. Ignored files
do not count. Native options use untracked=normal/no-ahead-behind and readonly
no-optional-locks/GIT_OPTIONAL_LOCKS=0, no lazy fetch, fsmonitor/untrackedCache off.

Reader checks actual root/common/admin/object-format, HEAD branch/OID and
root/.git device/inode before/after. Main admin must equal common; linked admin
must be a direct child under common/worktrees and its gitdir backlink must point
to this worktree's .git. Unsupported metadata types/leaf symlinks reject before
Git discovery. This prevents discovery into another clean repository or another
same-Node worktree from yielding a false clean. Lasting identity changes discard
that status. Separate-command observations are not claimed atomic.

Raw-byte finding was tested and grounded in official process 1.6.26.1 source
(System/Process/Posix.hs): cwd/environment use withFilePath, argv withCString.
Pinned-source Nix eval/build fetched the source (project legacyPackages lacks
haskellPackages, so use inputs.nixpkgs); no project dependencies changed. Reader
therefore clears inherited redirecting environment then sets verified absolute
GIT_DIR/GIT_WORK_TREE per invocation. Paths remain lossless without global
encoding changes/new transport. Fixtures first add at ASCII paths, filesystem-
rename to raw bytes and native worktree repair from raw cwd; byte filenames stage
through NUL stdin and rename with filesystem/native add. Tests assert actual raw
registration paths. Existing broader argv path call sites remain a known separate
boundary; do not assume their byte safety or expand this B4 work implicitly.

Added 18 groups (Status 70). Native SHA-1/SHA-256 x files/reftable covers all flags,
rename/unmerged/submodule (including ignore overrides), non-UTF-8/newline names
and worktree paths, text/JSON/CBOR and dirty 0, empty associations, locked/missing/
prunable entries, foreign separate-git-dir clean repo, missing .git, same-Node
wrong admin alias, change after status, main checkout, partial/malformed/global
registration failures and selected query costs. Default/tip/worktrees/remote
avoid status; status avoids cat-file/history. Index/HEAD/refs/data remain unchanged
even with forced stat-cache refresh and a hostile inherited GIT_INDEX_FILE.
Clean status plus ignored data or MERGE_HEAD still fails unchanged removal
preflight with the specific expected reason. No safety preflight was merged into
observation. Existing management/protocol/Hook suites remain intact and pass.

Final full authorized 300s/one-job/core nix flake check passes all 16 suites /
376 groups, -Wall -Werror and treefmt 61 eligible files/zero changes. Derivation:
/nix/store/fm2lda6kn55134mazsza57rx4jiddcz9-git-roam-0.2.0.drv.
Only x86_64-linux checked; other systems/minimum Git/10^4-Node timing unknown.
First check found lone-NUL acceptance and fixture path mismatch with surrogate
logging failure; second exposed the exact mismatch. Third full check passed
with the byte-safe pinning/fixture fix; fourth passed final text dirty-exit
assertions. No timeout/skipped test. All 63 final files match checked snapshot
by SHA-256: tmp/b4-check and tmp/b4-verification.json. Earlier manifests preserved.
Full diff reviewed, diff HEAD --check passes. Draft tmp/commit.md uses full
GitRoam.Application.Status scope, no Breaking footer, one coherent phase (split
not necessary, high identity/byte/parser coupling). No new raw archive/uncommitted
project parent needed. Await user review/commit; verify committed blobs before
grounding. B5 remains atomic management/Hook migration under a new instruction.

## Completed B5: independent validation and atomic caller migration

B4 entry commit was verified against all 63 files in the final B4 manifest.
B5 changes 23 project paths, including Application/Validation.hs and the new
validation-tests main. ValidationError moves out of Inspect; existing constructor
labels, diagnostic categories and exit mappings remain to preserve current CLI
behavior. ValidationEvidence is abstract; its read-only projection runs within
before/after complete local refs and a strictly successful history session.
loadManagedState validates the whole set with no presentation/worktree reads;
validateCandidate validates explicit refs with shallow/history/connectivity/
identity checks and no implicit live-ref enumeration. Callers retain their own
execution-time ref checks. Protocol decoder and raw transport are unchanged.

Create, Checkpoint, Delete and Undeploy call Worktree.loadOperationState, which
explicitly retains old Inspect's registration read/parse gate before identity
acceptance, inside ref-change and strict-session completion. Original operation
identity-error strings are preserved. All prepare, execution, compensation and
residual-state call sites migrated, not just initial loads. Deploy imports the
candidate validator and keeps its existing planning/ref safeguards. Hook accepts
an injected Git adapter, uses shared readNodeRefs plus requireCompleteRefs and
rejects symbolic Nodes. Private Hook ref enumeration/decoder removed; native
transaction-input parsing, local Content fast path, all-set conflict validation,
packed-ref pruning evidence and locks remain separate unchanged responsibilities.

Inspect is now only the legacy Check projection: node/history/worktree views and
problems. It has no reportManagedState, error/inference/candidate reexports or
compatibility-only wrappers. Production Inspect imports remain only in CLI and
Output. No Status observation enters trusted state. Check public output/scope,
Root/Content/Checkpoint protocol and all operation safety policies stay unchanged.
README and CHANGELOG TODO v0.3.0 describe B5; no package/lock/release metadata change.

Final isolated 65-file snapshot includes both untracked modules. Authorized
300s/single-job/core nix flake check returned exit 0 on x86_64-linux: all 17 suites
/ 400 groups pass, -Wall -Werror, treefmt 63 eligible files, zero changes. New
24 groups cover four format/backend combinations, no-worktree core loading,
identity mismatch, warned/malformed/duplicate/nonzero/transport ref failures,
native symbolic Node rejection including an unrelated Hook Node, ref-change
precedence, callback-success followed by native nonzero session shutdown, and
all management registration guards with exact failure cause, unchanged refs,
no ref/object/worktree write commands and absent created paths. Existing context,
missing objects, shallow, installed Hook, user-data/rollback and cancellation
regressions pass. No skipped test or timeout. Initial compilation found a missing
Delete import; fixed. Subsequent full checks passed; final review strengthened
operation assertions and added the explicit native Hook symbolic case, all in the
final verified snapshot. Product derivation:
/nix/store/dbc1kc7mzajzir1n3yhj5dd57fpwl6r4-git-roam-0.2.0.drv.
Only x86_64-linux verified; no minimum-version, other-system or 10^4-Node benchmark
claim. tmp/b5-verification.json contains the SHA-256 manifest and tmp/b5-check
contains source. Earlier intermediate manifests retained separately.

All current files equal the final snapshot; complete tracked/untracked diff
reviewed and diff --check passed. Full-phase tmp/commit.md uses
refactor(GitRoam.Application.Validation): separate protocol validation from inspection.
Split not necessary, high difficulty due to coupled validation and caller safety.
Project index empty, user commits. Completion memory has no parent for an
uncommitted B5; source/tests and durable findings suffice without raw archive.
Await review/commit and B6 instruction; verify committed blobs against the final
manifest before grounding. B6 changes Check report/tri-state validity and removes
remaining obsolete legacy presentation only as part of that next phase.

## Completed B4-fix after B5: relative linked-worktree backlinks

Baseline is the committed B5 snapshot, verified against all 65 final manifest
blobs with clean entry state. Four-path fix: Git.Status backlink resolution,
WorkingTreeStatus regressions, README and CHANGELOG Fixed under TODO v0.3.0.
Decode filesystem bytes, resolve relative backlinks from admin, then perform the
existing own-.git identity comparison. No new discovery, CLI/schema/model/protocol
or management change. Other identity, read-only and byte-path safeguards remain.

Native Git 2.56.0 confirms both explicit --relative-paths and
worktree.useRelativePaths=true produce relative .git, commondir and admin/gitdir.
Tests compare these with native Repository discovery's absolute root/admin/common
paths and query clean/dirty/clean from main and linked worktrees. They corrupt a
relative backlink immediately after native registration output; the registered
path then fails the exact identity check with unavailable and Node/property/path
diagnostic. Restoring it returns clean. Four new groups exercise both modes across
all object-format/ref-backend combinations. Absolute/non-UTF-8 and read-only
identity cases continue passing.

First full authorized 300s/single-job/core Nix check returned exit 0: x86_64-linux,
17 suites / 404 groups, Status 74, -Wall -Werror and treefmt 63 files zero changes.
Product /nix/store/0x9cm5fd4vrn0gysf0kbvqwj9kvk3qvd-git-roam-0.2.0.drv.
All 65 files match tmp/b4-fix-check and tmp/b4-fix-verification.json by SHA-256;
diff --check passes. No skipped tests, failure or timeout. Other platforms,
minimum Git and 10^4-Node timings remain unverified. No formatter was run on
project files; manual edits passed formatting check. No package/release/lock change.

Full four-file diff reviewed, project index empty; user stages/commits separately.
tmp/commit.md uses requested fix(GitRoam.Git.Status) title and complete fix diff.
Split not necessary, medium difficulty. Distilled findings and source/tests suffice
without raw archive. Completion checkpoint has no parent for uncommitted fix.
Verify the user's later commit against final manifest, then enter B6 on actual
HEAD. Original Check scope and strict B5 validation remain constraints for B6.

## Post-B1 requirements adopted for B2 and B5

The user refined the plan after inspecting actual B1. These requirements were
adopted before B2 implementation; B2 completion is recorded above, while the B5
requirements remain pending. Keep B1–B7 as seven nodes.

B2 must evolve the shared ref observation to retain independently reliable
partial results and diagnostics, while exposing an explicit completeness
judgment usable by strict callers. Status may report those reliable successes;
Inspect and management callers must still require complete acceptable evidence
before constructing or using trusted state. A collection of successful rows
alone is not proof of a complete ref set. Do not salvage ambiguous/conflicting
rows by guessing, or treat arbitrary stdout from a failed command as reliable
without evidence. The exact observation/result types remain an implementation
choice; no permanent compatibility wrapper is required.

B2 must also extend batch ref observation to obtain upstream information rather
than launch one Git query per Node. Use bounded batch ref/config observations as
needed to retain missing/ambiguous upstream configuration semantics; the exact
Git fields/commands need implementation verification. Cover absent upstream,
local remote='.', configured-but-missing resolved refs and ambiguous config
without inventing remote names. Adapter tracing must demonstrate that upstream
observation subprocess count does not grow linearly with Node count.

B2 acceptance must cover reliable successes retained alongside observation
failures/diagnostics, unavailable or ambiguous evidence not claimed successful,
and strict consumers rejecting incomplete observations even when usable rows
exist. Preserve existing protocol/preflight safety tests while changing the
reader's result model. Batch upstream tests must exercise multiple Nodes and
relevant object-format/ref-backend integration coverage.

B5 must migrate Protection Hook's ref enumeration to the shared reader, in
addition to migrating its candidate-validation dependency. Source inspection
at the committed B1 state confirms evaluateTransaction still has its own
for-each-ref and decodeRef path. Remove this duplicate enumeration/parser once
migrated; Hook transaction-input parsing and packed-ref pruning evidence remain
separate responsibilities. Require complete ref observations before candidate
validation; preserve duplicate/symbolic rejection, expected-old evidence,
Content fast-path versus whole-state validation, Root conflict checks and the
existing pack-refs/native deletion protections.

B5 must remove every management operation's dependency on InspectionReport for
ManagedState, including reportManagedState access. This reinforces the original
atomic caller migration: direct complete-state/candidate validators for Create,
Deploy, Undeploy, Delete, Checkpoint and Protection, with explicit worktree safety
preconditions where necessary. No conversion of partial Status into trusted
state and no permanent report adapter. Acceptance includes searches confirming
no management reportManagedState/InspectionReport dependency or duplicate Hook
ref enumeration remains, plus strict incomplete-observation and installed-Hook
transaction/safety regressions.

At adoption this addition changed planning only. B2 requirements are now
implemented and verified as recorded above; B5 Hook/management migrations are
now separately completed and verified in the B5 section, not inferred from B2.

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
   bytes and protocol-invalid history still observable. Extend shared ref
   observation for reliable partial successes plus explicit completeness for
   strict callers, and obtain upstream via batch reads rather than per-Node
   subprocesses. Test incomplete-result rejection and upstream process counts.
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
   coherent node; remove all management InspectionReport/ManagedState coupling.
   Migrate Protection Hook ref enumeration/parser to the shared reader with
   strict completeness enforcement. Audit implicit worktree preconditions.
   Preserve Create,
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
and explicit execution authorization control. None ran during initial planning;
B1/B2 execution evidence above supplies the actual current verification.

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

B1-B5 and their review corrections were committed by the user and verified
against their respective manifests. The relative-worktree B4-fix is complete and
verified in the uncommitted worktree; await its separate user commit before B6.
Only within this conversation / the
current Status-query redesign B1–B7, draft one commit message from the COMPLETE
stage diff immediately on completion of each later stage, even before
user staging. Review new files and tracked changes against the stage baseline;
if staged, use the complete staged diff and distinguish unrelated/unstaged work.
Use the principal full Haskell module name as scope, preserving capitalization,
as explicitly chosen for B1. Save the draft to validated tmp/commit.md. This
temporary message-drafting convention ends with this redesign; do not apply it
to unrelated work. It does not authorize project staging or commits, later-stage
implementation or additional check commands by itself.
