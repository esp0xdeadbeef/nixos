{ pkgs, lib, ... }:

let
  mk-nixos-vlan = import ./mk-nixos-vlan.nix { inherit pkgs lib; };

  vlanModule = mk-nixos-vlan {
    wan = {
      iface = "lan1010";
      dhcp4 = false;
      dhcp6 = false;
      ip4 = "10.255.255.2/30";
      gw4 = "10.255.255.1";
      ip6 = "fd42:dead:beef:100::2/64";
      gw6 = "fd42:dead:beef:100::1";
      acceptRA = true;
    };

lans = [
  {
    id = 7;
    name = "lan7";
    iface = "lan7";
    ip4 = "10.13.37.1/24";
    ip6 = "fd42:dead:beef:7::1/64";
    dhcp4 = true;
    ra6 = true;
  }
  {
    id = 3;
    name = "lan3";
    iface = "lan3";
    ip4 = "10.10.3.1/24";
    ip6 = "fd42:dead:beef:3::1/64";
    dhcp4 = true;
    ra6 = true;
  }
];


    domain = "lan.";
    upstreamDns = [ "9.9.9.9" "149.112.112.112" ];
    publicPrefixFile = "/run/secrets/subnet-ipv6";
  };
in
{
  imports = [ ./debugging-packages.nix  ./debug-packages.nix vlanModule ];
  system.stateVersion = "25.11";
}

