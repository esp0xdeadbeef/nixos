{ inputs
, lib
, outPath
, profiles
, ...
}:
let
  system = "x86_64-linux";
  hostName = "s-gamma";
  installDisk = "/dev/vda";
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.impermanence.module
    inputs.sops-nix.nixosModules.sops

    ./hardware.nix
    ./mail.nix

    (import ./disko.nix {
      disk = installDisk;
    })

    (import ./machine-base.nix {
      inherit lib outPath;
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inherit hostName installDisk;
    })
  ];

  system.stateVersion = "26.05";
}
