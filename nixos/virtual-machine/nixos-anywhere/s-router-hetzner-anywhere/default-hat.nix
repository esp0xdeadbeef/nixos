{ inputs
, lib
, ...
}:

{
  _module.args.sRouterNixosLabProfile = {
    labSource = "HAT/emulated-isp-residential-testnet";
    labSelector = "s-router-hetzner-anywhere";
  };
  networking.hostName = lib.mkForce "hetzner-nebula-prodtest-01";

  imports = [
    ./modules/host-substrate.nix
    (import ./renderers.nix {
      inherit inputs lib;
      labSource = "HAT/emulated-isp-residential-testnet";
      selectorFile = "nixos/virtual-machine/nixos-anywhere/s-router-hetzner-anywhere/default-hat.nix";
    })
  ];
}
