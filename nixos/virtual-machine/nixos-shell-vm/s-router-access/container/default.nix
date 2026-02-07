{
  pkgs,
  lib,
  config,
  outPath,
  ...
}:

let
  mk-nixos-vlan = import ./mk-nixos-vlan { inherit pkgs lib; };

  vlanModule = mk-nixos-vlan {
    wans = [
      {
        name = "s-router-edge";
        mark = "190";
        iface = "lan190";

        ip4 = "10.10.190.2/31";
        gw4 = "10.10.190.1";

        ip6 = "fd42:dead:beef:190::2/127";
        gw6 = "fd42:dead:beef:190::1/127";

        acceptRA = false;
        publicPrefixFile = "/run/secrets/subnet-ipv6";
      }
    ];

    lans = [
      {
        id = 10;
        name = "lan10";
        iface = "lan10";
        ip4 = "10.10.10.1/24";
        ip6 = "fd42:dead:beef:10::1/64";
        dhcp4 = true;
        ra6 = true;
      }
    ];

    domain = "lan.";
    upstreamDns = [
      "1.1.1.1"
      "9.9.9.9"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
  };
in
{
  imports = [
    ./debugging-packages.nix
    vlanModule
    ./make-vlan-bridges.nix
    ./nftables.nix
  ];

  services.resolved.enable = false;
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
  boot.isContainer = true;
  networking.firewall.enable = false;
}
