# Minimal hetzner test VM — SSH only, no routers, no renderers, no parent deps.
# Self-contained: all files copied here so sat.sh/s-router-hetz changes don't affect it.
{ inputs
, lib
, outPath
, profiles
, ...
}:
let
  system = "x86_64-linux";
  hostName = "hetz-test";
  installDisk = "/dev/sda";
in
{
  networking.hostName = lib.mkForce hostName;

  imports = [
    inputs.disko.nixosModules.disko
    profiles.nixos.impermanence.module
    inputs.sops-nix.nixosModules.sops

    ./hardware.nix

    (import ./disko.nix {
      disk = installDisk;
    })

    (import ./machine-base.nix {
      inherit lib outPath;
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      inherit hostName installDisk;
    })
  ];

  system.stateVersion = "25.11";
}
