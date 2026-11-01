{
  src,
  lib,
  git,
  haskell,
  haskellPackages,
}:
let
  package = haskell.lib.overrideCabal (haskellPackages.callCabal2nix "git-roam" src { }) (_: {
    doCheck = true;
    doHaddock = false;
    mainProgram = "git-roam";
  });
in
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ git ];
  GIT_ROAM_GIT = lib.getExe git;
})
