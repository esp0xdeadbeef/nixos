{ inputs, relativeRepo, ... }:
{
  additions = import ./additions.nix { inherit relativeRepo; };
  modifications = import ./modifications.nix { inherit inputs; };
  impermanence-module = import ./impermanence-module.nix { inherit inputs; };
  unstable-packages = import ./unstable-packages.nix { inherit inputs; };
  nixpkgs-25_11-packages = import ./nixpkgs-25_11-packages.nix { inherit inputs; };
  legcord-unstable-overwrite = import ./legcord-unstable-overwrite.nix;
}
