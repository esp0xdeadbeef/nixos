{ inputs
, lib
, ...
}:

{
  _module.args.sRouterNixosLabProfile = {
    labSource = "sat";
    labSelector = "s-router-nixos";
  };
  # single import to use the renderer expected here.
  networking.hostName = lib.mkForce "s-router-nixos";

  imports = [
    (import ./renderers.nix {
      inherit inputs lib;
      labSource = "sat";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos/default-sat.nix";
    })
  ];
}
