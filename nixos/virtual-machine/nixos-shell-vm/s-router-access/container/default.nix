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
      # Old configuration:
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
        ra6 = false;
      }

      # New configuration from here:

      # 10–19 Management / hypervisors
      {
        id = 10;
        name = "lan10";
        iface = "lan10";
        ip4 = "10.10.10.1/24";
        ip6 = "fd42:dead:beef:10::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 20–29 Servers / infra
      {
        id = 20;
        name = "lan20";
        iface = "lan20";
        ip4 = "10.10.20.1/24";
        ip6 = "fd42:dead:beef:20::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 30–39 User LAN
      {
        id = 30;
        name = "lan30";
        iface = "lan30";
        ip4 = "10.10.30.1/24";
        ip6 = "fd42:dead:beef:30::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 40–49 Work / corp-segmented
      {
        id = 40;
        name = "lan40";
        iface = "lan40";
        ip4 = "10.10.40.1/24";
        ip6 = "fd42:dead:beef:40::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 50–59 IoT / untrusted
      {
        id = 50;
        name = "lan50";
        iface = "lan50";
        ip4 = "10.10.50.1/24";
        ip6 = "fd42:dead:beef:50::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 60–69 DMZ
      {
        id = 60;
        name = "lan60";
        iface = "lan60";
        ip4 = "10.10.60.1/24";
        ip6 = "fd42:dead:beef:60::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 70–79 Lab / exploit / test
      {
        id = 70;
        name = "lan70";
        iface = "lan70";
        ip4 = "10.10.70.1/24";
        ip6 = "fd42:dead:beef:70::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 80–89 Observability / monitoring
      {
        id = 80;
        name = "lan80";
        iface = "lan80";
        ip4 = "10.10.80.1/24";
        ip6 = "fd42:dead:beef:80::1/64";
        dhcp4 = true;
        ra6 = true;
      }

      # 90–99 Transit / router links
      {
        id = 90;
        name = "lan90";
        iface = "lan90";
        ip4 = "10.10.90.1/24";
        ip6 = "fd42:dead:beef:90::1/64";
        dhcp4 = false;
        ra6 = false;
      }

      # 1000+ WAN / ISP / upstream
      #{
      #  id = 1000;
      #  name = "lan1000";
      #  iface = "lan1000";
      #  ip4 = "10.10.0.1/24";
      #  ip6 = "fd42:dead:beef:1000::1/64";
      #  dhcp4 = false;
      #  ra6 = false;
      #}

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
    #vlanModule
    #./make-vlan-bridges.nix
    #./nftables.nix
  ];
  services.resolved.enable = false;
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
  boot.isContainer = true;
  networking.firewall.enable = false;
}
