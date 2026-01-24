{ config, pkgs, ... }:
{
  environment.etc.hosts.enable = false;

  environment.systemPackages = with pkgs; [
    tcpdump
    neovim
    nmap
    nftables
    dig
  ];

}
