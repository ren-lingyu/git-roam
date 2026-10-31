{
  description = "Isolated Git 2.54.0 worktree batch experiment for Git-roam";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/885ba4d038f10c3d17d7a92e8c3cc185b99c9158";
    gitSource = {
      url = "github:git/git/94f057755b7941b321fd11fec1b2e3ca5313a4e0";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, gitSource, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      baselineGit = pkgs.gitMinimal.overrideAttrs (old: {
        version = "2.54.0-baseline";
        src = gitSource;
        makeFlags = (old.makeFlags or [ ]) ++ [ "NO_CURL=1" ];
        patches = [ ];
      });
      reuseGit = baselineGit.overrideAttrs (_: {
        version = "2.54.0-reuse";
        patches = [ ./patches/0001-reuse-worktree-list.patch ];
      });
    in
    {
      packages.x86_64-linux = {
        patched-git = (import nixpkgs { system = "x86_64-linux"; }).gitMinimal.overrideAttrs (old: {
          version = "2.54.0-git-roam-experiment";
          src = gitSource;
          makeFlags = (old.makeFlags or [ ]) ++ [ "NO_CURL=1" ];
          patches = [
            ./patches/0001-reuse-worktree-list.patch
            ./patches/0002-experimental-batch-add.patch
            ./patches/0003-safe-batch-validation-and-rollback.patch
          ];
        });
      };

      checks.x86_64-linux.smoke =
        (import nixpkgs { system = "x86_64-linux"; }).runCommand "git-roam-worktree-batch-smoke"
          {
            nativeBuildInputs = [ self.packages.x86_64-linux.patched-git ];
          }
          ''
            export GIT_BIN="${self.packages.x86_64-linux.patched-git}/bin/git"
            bash ${./smoke.sh}
            touch "$out"
          '';

      checks.x86_64-linux.benchmark = pkgs.runCommand "git-roam-worktree-benchmark"
        {
          nativeBuildInputs = [ pkgs.python3 ];
          BASELINE_GIT = "${baselineGit}/bin/git";
          REUSE_GIT = "${reuseGit}/bin/git";
          PATCHED_GIT = "${self.packages.x86_64-linux.patched-git}/bin/git";
        }
        ''
          python3 ${./benchmark.py}
          mkdir -p "$out"
          cp results.json "$out/results.json"
        '';

      checks.x86_64-linux.safety = pkgs.runCommand "git-roam-worktree-safety"
        {
          nativeBuildInputs = [ pkgs.python3 ];
          GIT_BIN = "${self.packages.x86_64-linux.patched-git}/bin/git";
        }
        ''
          python3 ${./safety.py}
          touch "$out"
        '';
    };
}
