{
  description = "Isolated Git-roam raw object reader performance experiment";
  inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&rev=885ba4d038f10c3d17d7a92e8c3cc185b99c9158&shallow=1";
  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    library = pkgs.callPackage ./source/pkgs/git-roam/package.nix {
      src = pkgs.lib.fileset.toSource { root = ./source/cabal; fileset = ./source/cabal; };
      haskellPackages = pkgs.haskell.packages.ghc912;
    };
    compiler = pkgs.haskell.packages.ghc912.ghcWithPackages (hp: [
      library hp.process hp.cryptohash-sha256
      hp.bytestring hp.containers
    ]);
    harness = pkgs.runCommand "git-roam-reader-harness" {
      nativeBuildInputs = [ compiler ];
      meta.mainProgram = "reader-harness";
    } ''
      mkdir -p "$out/bin"
      ghc -O2 -threaded -rtsopts -with-rtsopts="-N1 -M512m" -odir . -hidir . ${./Experiment.hs} -o "$out/bin/reader-harness"
    '';
    runner = pkgs.writeShellApplication {
      name = "object-read-performance";
      runtimeInputs = [ pkgs.python3 pkgs.git pkgs.time pkgs.coreutils harness ];
      text = ''
        exec python3 ${./run.py} --git ${pkgs.lib.getExe pkgs.git} \
          --harness ${pkgs.lib.getExe harness} --time ${pkgs.time}/bin/time \
          --timeout ${pkgs.coreutils}/bin/timeout --source-manifest ${./SOURCE.json} "$@"
      '';
    };
  in {
    packages.${system}.default = runner;
    apps.${system}.default = { type = "app"; program = "${runner}/bin/object-read-performance"; };
  };
}
