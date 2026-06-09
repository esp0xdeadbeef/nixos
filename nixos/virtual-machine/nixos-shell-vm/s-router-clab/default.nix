{ inputs
, lib
, outPath
, ...
}:
let
  labSource = "HAT/emulated-isp-residential-testnet";
in
{
  _module.args.sRouterClabLabProfile = {
    inherit labSource;
    labSelector = "s-router-clab";
    deploymentHost = "s-router-clab";
  };

  networking.hostName = lib.mkForce "s-router-clab";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./management-vlan2.nix
    ./host-adapter-guard.nix

    (import ./renderers.nix {
      inherit inputs lib;
      inherit labSource;

      system = "x86_64-linux";

      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-clab/default.nix";
    })
  ];
}
