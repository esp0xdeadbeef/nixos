{ inputs, relativeRepo, ... }:
{
  additions = import ./additions.nix { inherit relativeRepo; };
  modifications = import ./modifications.nix { inherit inputs; };
  unstable-packages = import ./unstable-packages.nix { inherit inputs; };
  nixpkgs-25_11-packages = import ./nixpkgs-25_11-packages.nix { inherit inputs; };
  angr-nixpkgs-25_11-overwrite = import ./angr-nixpkgs-25_11-overwrite.nix;
  emudhra-ca-distrust = import ./emudhra-ca-distrust.nix;
  git-skip-tests = import ./git-skip-tests.nix;
  nix-manual-manpages-only = import ./nix-manual-manpages-only.nix;
}
