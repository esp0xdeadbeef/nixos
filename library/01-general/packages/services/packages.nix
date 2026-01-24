{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    samba4Full
  ];
}