{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nmap
    wget
    traceroute
    dig
  ];
}
