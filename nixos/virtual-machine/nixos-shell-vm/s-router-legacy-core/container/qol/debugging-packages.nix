{ pkgs, lib, ... }:
{
  programs.neovim = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [
    traceroute
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
