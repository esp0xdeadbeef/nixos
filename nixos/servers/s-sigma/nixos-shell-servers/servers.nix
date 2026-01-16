{
  lib,
  pkgs,
  self,
  ...
}:

let
  mkVM = import ./mk-nixos-shell-vm.nix { inherit pkgs lib self; };
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
    (mkVM "s-sigma-s-router-edge" {
      description = "s-router-edge VM (nixos-shell)";
      keep = 1;
      #repository = "path:/home/deadbeef/github/nixos";
      repository = "path:/home/deadbeef/github/nixos";
    })

    (mkVM "s-gameservers" {
      description = "Gameserver VM (nixos-shell)";
      keep = 1;
    })
    (mkVM "s-sigma-s-router-vpn-egress" {
      description = "VPN-egress VM (nixos-shell)";
      keep = 1;
      repository = "path:/home/deadbeef/github/nixos";
    })

    (mkVM "s-test-vm-impermanence" {
      description = "s-test-vm (nixos-shell)";
      keep = 1;
    })
  ];
}
