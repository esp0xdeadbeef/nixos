{ pkgs, lib, ... }:

let
  mk-nixos-vlan = import ./mk-nixos-vlan { inherit pkgs lib; };

  vlanModule = mk-nixos-vlan {
    wans = [
      {
        name = "wanA";
        mark = "1010";
        iface = "lan1010";

        ip4 = "10.255.255.2/29";
        gw4 = "10.255.255.1";

        ip6 = "fd42:dead:beef:100::2/64";
        gw6 = "fd42:dead:beef:100::1";
        acceptRA = true;

        publicPrefixFile = "/run/secrets/subnet-ipv6";
      }
    ];

    lans = [
      {
        id = 2;
        name = "lan2";
        iface = "lan2";
        ip4 = "192.168.1.1/24";
        ip6 = "fd42:1::1/64";
        dhcp4 = true;
        ra6 = false;

        runtimeHostsFile = "/run/secrets/vlan2-hostnames-servers.json";
      }

      {
        id = 3;
        name = "lan3";
        iface = "lan3";
        ip4 = "10.10.3.1/24";
        ip6 = "fd42:dead:beef:3::1/64";
        dhcp4 = true;
        ra6 = false;
      }

      {
        id = 7;
        name = "lan7";
        iface = "lan7";
        ip4 = "10.13.37.1/24";
        ip6 = "fd42:dead:beef:7::1/64";
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
  ];
  services.resolved.enable = false;
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
  boot.isContainer = true;
  networking.firewall.enable = false;
}
