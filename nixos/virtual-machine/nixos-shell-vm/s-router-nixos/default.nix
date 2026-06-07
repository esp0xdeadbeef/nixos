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
    labSource = labSource;
    labSelector = "s-router-nixos";
  };
  # single import to use the renderer expected here.
  networking.hostName = lib.mkForce "s-router-nixos";

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"

    (import ./renderers.nix {
      inherit inputs lib;
      labSource = labSource; 
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos/default.nix";
    })
  ];
}
