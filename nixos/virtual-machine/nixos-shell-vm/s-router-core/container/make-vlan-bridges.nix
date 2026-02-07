# ./container/make-vlan-bridges.nix
{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  mkBridge = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix" {
    inherit lib pkgs;
  };
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ############################
  # 1) VLAN tagging on trunks
  ############################

  # LAN trunk: tag transit + legacy
  systemd.network.networks."10-lan-trunk" = {
    matchConfig.Name = "lan";
    networkConfig = {
      DHCP = "no";
      VLAN = [
        "lan.100"
        "lan.1010"
      ];
    };
  };

  # WAN trunk: tag ISP VLAN6
  systemd.network.networks."10-wan-trunk" = {
    matchConfig.Name = "wan";
    networkConfig = {
      DHCP = "no";
      VLAN = [
        "wan.6"
      ];
    };
  };

  ############################
  # 2) Bridges (your technique)
  ############################
  imports = [
    # Legacy invariant (MUST exist)
    (mkBridge "lan" 1010 { bridge = "br-vlan1010"; })

    # Transit link
    (mkBridge "lan" 100 { bridge = "br-transit100"; })

    # WAN handoff for PPPoE (MUST exist)
    (mkBridge "wan" 6 { bridge = "br-wan6"; })
  ];
}

