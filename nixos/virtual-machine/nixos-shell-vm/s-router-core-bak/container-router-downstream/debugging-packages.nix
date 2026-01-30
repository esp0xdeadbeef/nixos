{ pkgs, lib, ... }:
{

  environment.systemPackages = with pkgs; [
    nmap
    dnsutils
    radvd
    dhcpcd
    networkmanager
    ppp
    iproute2
    tcpdump
    tmux
    kea
  ];
}
