# mk-nixos-vlan.nix
{ pkgs, lib }:
args@{ ... }:
{ config, ... }:

let
  helpers = import ./mk-nixos-vlan/helpers.nix { inherit lib; };
in
{
  imports = [
    (import ./mk-nixos-vlan/networkd.nix {
      inherit pkgs lib helpers args;
    })
    (import ./mk-nixos-vlan/nftables.nix { inherit lib args; })
    (import ./mk-nixos-vlan/kea.nix {
      inherit pkgs lib helpers args;
    })
    (import ./mk-nixos-vlan/kea-services.nix { inherit pkgs lib args; })
    (import ./mk-nixos-vlan/radvd.nix { inherit pkgs lib args; })
  ];

  services.resolved.enable = false;
  networking.useHostResolvConf = lib.mkForce false;
}

