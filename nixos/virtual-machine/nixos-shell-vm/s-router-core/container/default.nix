{
  config,
  pkgs,
  lib,
  outPath,
  inputs,
  vid,
  guestIf,
  ...
}:

let
  lanIf = guestIf;

  fabricLib = inputs.nixos-network-compiler.lib;
in
{
  boot.isContainer = true;
  system.stateVersion = "25.11";

  networking.hostName = "s-router-core-vpn-${toString vid}";
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useHostResolvConf = false;

  # fallback DNS so curl works even if DHCP DNS isn’t present
  networking.nameservers = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  ############################################################
  # DHCP on unique uplink interface
  ############################################################
  systemd.network.networks = {
    "20-uplink-dhcp" = {
      matchConfig.Name = lanIf;
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = false;
    };
  };

  environment.systemPackages = with pkgs; [
    iproute2
    iputils
    tcpdump
    nftables
    curl
  ];

  networking.firewall.enable = false;
  services.resolved.enable = true;
}

