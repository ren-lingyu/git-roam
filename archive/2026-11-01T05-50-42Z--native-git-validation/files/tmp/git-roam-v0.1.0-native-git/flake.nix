{
  description = "Isolated standard Git behavior validation for Git Roam v0.1.0";

  inputs.nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&rev=885ba4d038f10c3d17d7a92e8c3cc185b99c9158&shallow=1";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      experiment = pkgs: pkgs.runCommand "git-roam-native-git-validation" {
        nativeBuildInputs = [ pkgs.git pkgs.python3 ];
        preferLocalBuild = true;
      } (
        "mkdir -p \"$out\"\n"
        + "python3 ${./validate.py}"
        + " --git " + pkgs.lib.getExe pkgs.git
        + " --workspace \"$TMPDIR/native-git\" --output \"$out\"\n"
      );
    in {
      packages = forSystems (pkgs: { default = experiment pkgs; });
      checks = forSystems (pkgs: { native-git = experiment pkgs; });
    };
}
