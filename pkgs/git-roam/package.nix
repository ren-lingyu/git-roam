{
  src,
  haskell,
  haskellPackages,
}:
haskell.lib.overrideCabal (haskellPackages.callCabal2nix "git-roam" src { }) (_: {
  doCheck = true;
  doHaddock = false;
  mainProgram = "git-roam";
})
