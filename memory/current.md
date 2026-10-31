# Git Roam current state

## Objective and outcome

The user requested a buildable, checkable empty Haskell project, using the
neighboring git-agent-workflow repository as a reference. The bootstrap is
complete and committed on the project branch. No application features or
external issue/PR were identified. Await the user's next project objective.

## Project baseline

- `cabal/cabal.project` selects the local package.
- `cabal/git-roam.cabal` defines version 0.1.0 and executable `git-roam`,
  with Haskell2010, `-Wall`, and only `base >=4.16 && <5`.
- `cabal/app/Main.hs` implements `main = pure ()`: success without output or
  actions. There is no library or test suite.
- `flake.nix` uses locked nixpkgs and personal-nixpkgs inputs. `pkgs/`
  provides the overlay and Cabal-to-Nix packaging, with checks enabled and
  Haddock disabled. Flake outputs include the default package, package check,
  and treefmt check. Systems: x86_64-linux, aarch64-linux, aarch64-darwin.
- README.org currently contains only title and author. The user explicitly
  confirmed this was their manual edit. Preserve it; do not restore the
  earlier agent-written build instructions.

## Verification

During bootstrap, the agent successfully ran on x86_64-linux:

```sh
timeout 120s nix build --no-link --no-write-lock-file -L path:.#default
timeout 120s nix flake check --no-write-lock-file -L path:.
```

The build used GHC 9.10.3; the final formatting check made zero changes.
These runs used the earlier uncommitted worktree, including a longer README.
No exact original committed provenance is asserted for those runs.

After committing and confirming the README edit, the user supplied successful
output from `nix flake check` (exit 0) for the current project state. It resolved
the same package derivation as the earlier successful build and reported
"all checks passed", with zero checks needing execution. This is user-supplied
validation evidence, not a fresh agent-run check. Other architectures were
omitted as incompatible with the host. No test suites exist.

`nix fmt` forwards positional arguments to its formatter, so `path:.` is not
a flake selector there. The installed Nix rejects `--flake`. Local help supports
`nix fmt --no-write-lock-file` from the repository root. Neither attempted
explicit-selector formatting command succeeded; the earlier README formatting
was corrected directly from the treefmt diff.

## Memory and continuation

The user initialized and deployed formal GAW after committing the bootstrap.
Public status/check confirmed a valid selector, canonical protection hook,
and ready worktree. This is the initial substantive memory baseline, based on
the bootstrap conversation, current repository inspection, and supplied check
result. Minor retries and the superseded waiting-for-commit state do not have
independent checkpoint value.

The associated project snapshot was inspected after the bootstrap commit.
Its source/build configuration match the earlier validated implementation;
the intentional README change and subsequent user validation are described
above. Project parents record inspected state, not proof of agent-run tests.

An untracked `CHANGELOG.org` is present. Its contents were not read or modified
in this task. Do not stage or edit it as part of memory maintenance.

Future project build/check/format commands require authorization under the
user's workspace policy; earlier one-time approvals are spent. Normal GAW
memory maintenance is authorized separately from project Git mutations.
