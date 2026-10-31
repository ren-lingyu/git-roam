{
  description = "Git Roam";

  inputs = {
    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&shallow=1";
    };
    personal-nixpkgs = {
      url = "git+https://github.com/ren-lingyu/nixpkgs.git?ref=refs/heads/main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    inputs.personal-nixpkgs.lib.mkFlake inputs.nixpkgs
      ({ lib }: rec {
        inherit inputs;
        moduleLocation = __curPos.file;
        llib = inputs.personal-nixpkgs.lib.mergeAttrsRecursive { allowOverrides = false; } [
          { inherit (inputs.personal-nixpkgs.lib) packages; }
        ];
        lpkgs = import ./pkgs {
          inherit llib;
          inherit (specialArgs) src;
        };
        specialArgs = {
          src = lib.fileset.toSource {
            root = ./cabal;
            fileset = lib.fileset.unions [ ./cabal ];
          };
        };
      })
      (
        { lpkgs, ... }: {
          config = {
            systems = [
              "x86_64-linux"
              "aarch64-linux"
              "aarch64-darwin"
            ];

            flake.overlays.default = lpkgs.overlays.default;

            perSystem = { pkgs, config, ... }: {
              nixpkgs.overlays = [ lpkgs.overlays.legacy ];

              legacyPackages = pkgs.legacyPackages;

              packages = {
                inherit (pkgs) git-roam;
                default = pkgs.git-roam;
              };

              checks = { inherit (pkgs) git-roam; };

              treefmt = {
                flakeCheck = true;
                settings.excludes = [
                  "LICENSE"
                  "flake.lock"
                ];
              };
            };
          };
        }
      );
}
