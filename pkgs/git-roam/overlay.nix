{ extraArgs }: final_: prev_: {
  git-roam = final_.callPackage ./package.nix {
    inherit (extraArgs) src;
    haskellPackages = final_.haskell.packages.ghc912;
  };
}
