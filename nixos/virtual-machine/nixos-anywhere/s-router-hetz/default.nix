{ inputs
, lib
, outPath
, ...
}:
let
  labSource = "active-lab";
  hostName = "s-router-hetz";
  system = "x86_64-linux";

  # Do not hardcode /dev/sda for a real Hetzner host unless you verified it.
  # Prefer:
  #   ls -l /dev/disk/by-id/
  #
  # Examples:
  #   /dev/disk/by-id/ata-SAMSUNG_...
  #   /dev/disk/by-id/nvme-SAMSUNG_...
  installDisk = "/dev/sda";

  cpmResult = inputs.network-control-plane-model.libBySystem.${system}.compileAndBuildFromPaths {
    inputPath = "${inputs.network-labs}/${labSource}/intent.nix";
    inventoryPath = "${inputs.network-labs}/${labSource}/inventory-nixos.nix";
  };
in
{
  _module.args.sRouterNixosLabProfile = {
    inherit labSource;
    labSelector = hostName;
  };

  networking.hostName = lib.mkForce hostName;

  imports = [
    # Required because ./disko.nix only defines disko.devices.
    # Without this module, disko.devices is not a valid option.
    inputs.disko.nixosModules.disko

    # Required because /persist is part of the machine contract.
    inputs.impermanence.nixosModules.impermanence

    # Required if renderer/imported sops files define sops.* options.
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

    (import ./renderers.nix {
      inherit inputs lib system hostName;
      cpm = cpmResult.control_plane_model;
    })
  ];
}
