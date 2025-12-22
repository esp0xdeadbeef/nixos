{ pkgs, lib, ... }:

{
  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;

  environment.systemPackages = with pkgs; [
    traceroute
    nmap
    dnsutils
    radvd
    ppp
    iproute2
    tcpdump
    tmux
    kea
  ];
}
