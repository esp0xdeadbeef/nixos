{ inputs
, lib
, ...
}:

{
  _module.args.sRouterNixosLabProfile = {
    labSource = "HAT/emulated-isp-residential-testnet";
    labSelector = "s-router-nixos";
  };
  # single import to use the renderer expected here.
  networking.hostName = lib.mkForce "s-router-nixos";

  imports = [
    (import ./renderers.nix {
      inherit inputs lib;
      labSource = "HAT/emulated-isp-residential-testnet";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos/default-hat.nix";
    })
  ];
}
