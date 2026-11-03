{ inputs
, lib
, relativeRepo
, profiles
, ...
}:
let
  labSource = "active-lab";
  vmNics = [
    {
      nicId = "nic0";
      bridge = "vmbr4";
    }
    {
      nicId = "nic1";
      bridge = "vmbr4";
    }
    {
      nicId = "nic2";
      bridge = "vmbr4";
    }
    {
      nicId = "nic3";
      bridge = "vmbr4";
    }
    {
      nicId = "nic4";
      bridge = "vmbr4";
    }
    {
      nicId = "nic5";
      bridge = "vmbr4";
    }
  ];
in
{
  _module.args.sRouterNixosLabProfile = {
    inherit labSource;
    labSelector = "s-router-nixos";
  };

  networking.hostName = lib.mkForce "s-router-nixos";

  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.network.router-vlan2-runtime-contract

    (import ./renderers.nix {
      inherit inputs lib relativeRepo;
      inherit labSource vmNics;

      system = "x86_64-linux";

      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos/default.nix";
    })
  ];
}
