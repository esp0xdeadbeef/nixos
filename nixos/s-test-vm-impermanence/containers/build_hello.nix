{
  config,
  pkgs,
  lib,
  ...
}:
{
  system.stateVersion = "25.05";

  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = true;
  networking.useDHCP = lib.mkDefault false;
  networking.interfaces.wan.useDHCP = true;

  networking.interfaces.lan.ipv4.addresses = [
    {
      address = "10.90.0.1";
      prefixLength = 24;
    }
  ];

  environment.systemPackages = with pkgs; [
    dnsutils
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];
}
