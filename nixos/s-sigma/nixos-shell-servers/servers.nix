{ lib, pkgs, ... }:

let
  mkVM = import ./mk-nixos-shell-vm.nix { inherit pkgs lib; };
in
{
  config = lib.mkMerge [
    (mkVM "s-infra" {
      description = "Infra VM (nixos-shell)";
      keep = 1;
      extraTmpfiles = [
        "d /persist/infra/unifi 0755 root root -"
      ];
    })

    (mkVM "s-gameservers" {
      description = "Gameserver VM (nixos-shell)";
      keep = 2;
    })
    (mkVM "s-sigma-s-router-vpn-egress" {
      description = "Gameserver VM (nixos-shell)";
      keep = 2;
    })
  ];
}

