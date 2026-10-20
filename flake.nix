# Builds the plugin with Nix, the way Mochi builds it from the lock file:
#
# - `mochi plugins install` uses it when Nix is installed.
# - home-manager takes the package as
#   `programs.mochi.plugins.wallpaper-selector.package = inputs.mochi-wallpaper-selector.packages.${pkgs.system}.default;`
#   or builds the source itself with `programs.mochi.plugins.wallpaper-selector.src`.
{
  description = "A Mochi plugin: pick a wallpaper on the island";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mochi = {
      url = "github:DavidutzDev/mochi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, mochi, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = mochi.lib.buildPlugin pkgs { src = ./.; };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            cargo
            rustc
            clippy
            rustfmt
          ];
        };
      });
    };
}
