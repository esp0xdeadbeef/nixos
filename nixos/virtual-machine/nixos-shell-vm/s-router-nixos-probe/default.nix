{ inputs, lib, relativeRepo, profiles, ... }:
let
  labSource = "probe-lab";
in
{
  _module.args.sRouterNixosLabProfile = {
    inherit labSource;
    labSelector = "s-router-nixos";
  };
  networking.hostName = lib.mkForce "s-router-nixos";
  imports = [
    (relativeRepo.module "library/10-vms/nixos-shell-vm/host-config-routers-without-network")
    profiles.nixos.nixpkgs.local-overlays
    (import ../s-router-nixos/renderers.nix {
      inherit inputs lib relativeRepo labSource;
      system = "x86_64-linux";
      hostName = "s-router-nixos";
      selectorFile = "nixos/virtual-machine/nixos-shell-vm/s-router-nixos-probe/default.nix";
    })
  ];
  system.stateVersion = lib.mkForce "26.05";
}
