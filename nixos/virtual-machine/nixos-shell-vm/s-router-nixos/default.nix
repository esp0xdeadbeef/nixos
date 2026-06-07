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
    labSelector = "s-router-nixos";
  };

  networking.hostName = lib.mkForce "s-router-nixos";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./management-vlan2.nix

    (import ./renderers.nix {
      inherit inputs lib;
      inherit labSource;

      system = "x86_64-linux";

      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos/default.nix";
    })
  ];
}
