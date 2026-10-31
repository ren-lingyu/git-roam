{ extraArgs }: final_: prev_: {
  git-roam = final_.callPackage ./package.nix { inherit (extraArgs) src; };
}
