# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  android-emulator-sdk = pkgs.callPackage ./android-emulator-sdk { };
  autorecon = pkgs.callPackage ./autorecon { };
  mxbuild = pkgs.callPackage ./mxbuild { };
  pentest-powershell = pkgs.callPackage ./pentest-powershell { };
  pentest-workspace = pkgs.callPackage ./pentest-workspace { };
}
