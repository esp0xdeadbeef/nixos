{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    fast-cli
    nmap
    wget
    traceroute
    dig
  ];
}
