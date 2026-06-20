# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  mxbuild = pkgs.callPackage ./mxbuild { };
  pentest-powershell = pkgs.callPackage ./pentest-powershell { };
}
