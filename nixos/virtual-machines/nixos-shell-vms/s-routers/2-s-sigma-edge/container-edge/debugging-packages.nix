{ pkgs, lib, ... }:
{

  environment.systemPackages = with pkgs; [
    traceroute
    nmap
    dnsutils
    ppp
    iproute2
    tcpdump
    tmux
    kea
    dhcpcd
    networkmanager
  ];

}
