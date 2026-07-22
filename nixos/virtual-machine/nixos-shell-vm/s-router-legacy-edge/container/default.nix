{ pkgs
, lib
, config
, relativeRepo
, ...
}:

let
  mk-nixos-vlan = import ./mk-nixos-vlan { inherit pkgs lib; };

  vlanModule = mk-nixos-vlan {
    wans = [
      {
        name = "wanA";
        mark = "1010";
        iface = "lan1010";

        ip4 = "10.255.255.3/29";
        gw4 = "10.255.255.1";

        ip6 = "fd42:dead:beef:1000::3/64";
        gw6 = "fd42:dead:beef:1000::1";
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
        id = 7;
        name = "lan7";
        iface = "lan7";
        ip4 = "192.168.2.1/24";
        ip6 = "fd42:dead:beef:7::1/64";
        dhcp4 = true;
        ra6 = false;
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
