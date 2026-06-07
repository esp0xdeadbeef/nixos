{ inputs
, lib
, outPath
, ...
}:
let
  labSource = "active-lab";
in
{
  _module.args.sRouterNixosLabProfile = {
    inherit labSource;
    labSelector = "s-router-hetz";
  };

  networking.hostName = lib.mkForce "s-router-hetz";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./management-vlan2.nix

    (import ./renderers.nix {
      inherit inputs lib;
      inherit labSource;

      system = "x86_64-linux";

      selectorFile = "nixos/virtual-machine/nixos-anywhere/s-router-hetz/default.nix";
    })
  ];
}
