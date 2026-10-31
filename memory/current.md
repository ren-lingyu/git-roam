# Git Roam current state

## Objective and implementation status

The current effective design is adopted from the supplied design document with
the user's explicit confirmation. It defines the intended v0.1.0 product;
the application still consists only of a buildable Haskell skeleton.
The independent local worktree experiment is complete and archived. Current
design knowledge is maintained directly, without replaying past design stages.

## Reading navigation

The project skill starts here. All memory/archive references belong to this
formal GAW worktree; Markdown links below resolve relative to this file.

- [design.md](design.md): current product goals, permanent Git protocol,
  operational constraints, and the reasons needed to apply them.
- [implementation.md](implementation.md): intended v0.1.0 loop, implementation
  guidance, open interface decisions, acceptance scenarios, and exclusions.
- [experiment.md](experiment.md): actual local worktree results, packaging
  preference, limitations, and independent archive provenance.
- [Independent experiment manifest](../archive/2026-10-31T06-58-49Z--worktree-batch-experiment/MANIFEST.md):
  the selected original experiment inputs/results and labelled log excerpts.

The product's Root/Content/Checkpoint terminology does not redefine GAW's
workflow. Adopted design does not mean implemented behavior or execution
authorization. The project skill remains a navigation entry point; concrete
facts and requirements belong in memory.

## Actual project baseline

Project paths in this section are relative to the ordinary project worktree.

- `cabal/cabal.project` selects the local package. `cabal/git-roam.cabal`
  defines version 0.1.0 and an executable using Haskell2010, `-Wall`, and
  `base >=4.16 && <5`.
- `cabal/app/Main.hs` is `main = pure ()`: no output or application actions.
  There is no library or test suite, and no implemented Node, Checkpoint,
  Hook, history validator, or deployment feature.
- `flake.nix` uses locked nixpkgs/personal-nixpkgs and `pkgs/` packaging to
  expose a default package, package check, and treefmt check. Systems declared
  are x86_64-linux, aarch64-linux, and aarch64-darwin. Packaging enables checks
  and disables Haddock. No experimental Git is wired into the application.
- The user deliberately kept `README.org` as title/author only. Preserve it;
  do not restore the earlier agent-written instructions.
- `CHANGELOG.org` uses the canonical Org header, `TODO 0.1.0`, and an empty
  `Added` category by explicit user choice because no substantive feature
  exists yet. Do not restore no-op-executable or Nix-scaffolding descriptions,
  add release dates, or infer release finalization.

## Verification boundaries

The earlier skeleton build and flake check succeeded on x86_64-linux, using
GHC 9.10.3. Agent runs used the uncommitted skeleton and a longer README; the
user supplied a successful flake check after their README edit and before
CHANGELOG initialization. Those observations are not a fresh validation of
every later committed tree. Other declared architectures were omitted, and
no product test suite exists.

Local worktree reproduction has its own inputs, checks, and archived evidence;
its successful outcomes do not validate the proposed application protocol,
Hook behavior, or the entire first-version test matrix. See the dedicated
memory files rather than treating document-supplied historical experiment
claims as locally reproduced facts.

The design baseline is reviewed against the source text and current project
files. No fresh application build/test, formatter run, or new experiment
validation accompanies this knowledge update. The ZIP is a knowledge source,
not newly archived raw evidence. Existing archive snapshots remain immutable.

## Next action and operating boundary

Use the adopted design and implementation boundaries to prepare a separately
scoped implementation plan, resolving the relevant open choices before coding.
No application implementation is implied by this memory update.

Future project edits, builds/checks/formatting, dependency/network operations,
and project Git mutations require their applicable authorization. Previous
experiment command approvals belonged to that completed task. Continue normal
GAW memory maintenance through its public interfaces and the active user policy.
