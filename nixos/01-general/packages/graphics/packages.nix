{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    glxinfo
  ];
}