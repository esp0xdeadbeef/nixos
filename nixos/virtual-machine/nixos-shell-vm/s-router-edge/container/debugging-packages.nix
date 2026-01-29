{ pkgs, lib, ... }:
{

  environment.systemPackages = with pkgs; [
    conntrack-tools
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
    dig
    neovim
    nftables
    netexec
  ];

  environment.etc.hosts.enable = false;
}
