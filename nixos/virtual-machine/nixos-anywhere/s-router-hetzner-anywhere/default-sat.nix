{ inputs
, lib
, ...
}:

{
  _module.args.sRouterNixosLabProfile = {
    labSource = "sat";
    labSelector = "s-router-hetzner-anywhere";
  };
  networking.hostName = lib.mkForce "hetzner-nebula-prodtest-01";

  imports = [
    ./modules/host-substrate.nix
    (import ./renderers.nix {
      inherit inputs lib;
      labSource = "sat";
      selectorFile = "nixos/virtual-machine/nixos-anywhere/s-router-hetzner-anywhere/default-sat.nix";
    })
  ];
}
