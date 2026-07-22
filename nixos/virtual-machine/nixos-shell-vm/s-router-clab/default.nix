{ inputs
, lib
, relativeRepo
, profiles
, ...
}:
let
  labSource = "active-lab";
in
{
  _module.args.sRouterClabLabProfile = {
    inherit labSource;
    labSelector = "s-router-clab";
  };

  networking.hostName = lib.mkForce "s-router-clab";

  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.network.router-vlan2-runtime-contract

    (import ./renderers.nix {
      inherit inputs lib;
      inherit labSource;

      system = "x86_64-linux";

      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-clab/default.nix";
    })
  ];
}
