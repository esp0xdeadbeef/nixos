{ pkgs, lib, ... }:
{

  environment.systemPackages = with pkgs; [
    nmap
    dnsutils
    ppp
    iproute2
    tcpdump
    tmux
    kea
  ];

}
