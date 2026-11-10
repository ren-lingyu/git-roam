{
  description = "Isolated v0.2.0 raw reader and shared-ancestry measurements";
  inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&rev=885ba4d038f10c3d17d7a92e8c3cc185b99c9158&shallow=1";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    # The exact production source passed 250 cases independently before this
    # experiment. Do not repeat that matrix for benchmark-only package copies.
    package = source: pkgs.haskell.lib.dontCheck (import (source + "/pkgs/git-roam/package.nix") {
      inherit (pkgs) lib git haskell;
      src = pkgs.lib.fileset.toSource { root = source + "/cabal"; fileset = source + "/cabal"; };
      haskellPackages = pkgs.haskell.packages.ghc912;
    });
    nativeLibrary = package ./source;
    legacyLibrary = package ./legacy-source;
    harness = label: library: let
      compiler = pkgs.haskell.packages.ghc912.ghcWithPackages (hp: [
        library hp.process hp.cryptohash-sha256 hp.bytestring hp.containers
      ]);
    in pkgs.runCommand ("git-roam-v020-harness-" + label) {
      nativeBuildInputs = [ compiler ];
      meta.mainProgram = "harness";
    } ''
      mkdir -p "$out/bin"
      ghc -O2 -threaded -rtsopts -with-rtsopts="-N1 -M1G" -odir . -hidir . ${./Experiment.hs} -o "$out/bin/harness"
    '';
    nativeHarness = harness "native" nativeLibrary;
    legacyHarness = harness "legacy-control" legacyLibrary;
    runner = pkgs.writeShellApplication {
      name = "v020-performance";
      runtimeInputs = [ pkgs.python3 pkgs.git pkgs.time pkgs.coreutils ];
      text = ''
        exec python3 ${./run.py} --git ${pkgs.lib.getExe pkgs.git} \
          --native ${pkgs.lib.getExe nativeHarness} --legacy ${pkgs.lib.getExe legacyHarness} \
          --time ${pkgs.time}/bin/time --timeout ${pkgs.coreutils}/bin/timeout \
          --source-manifest ${./SOURCE.json} --fixture-recipe ${./fixture.py} \
          --harness-source ${./Experiment.hs} "$@"
      '';
    };
  in {
    packages.${system}.default = runner;
    apps.${system}.default = { type = "app"; program = "${runner}/bin/v020-performance"; meta.description = "Bounded serial v0.2.0 performance experiment"; };
  };
}
