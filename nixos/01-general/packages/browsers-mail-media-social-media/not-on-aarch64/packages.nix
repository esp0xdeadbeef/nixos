{ config, pkgs, ... }:
{

  environment.systemPackages = with pkgs; [
    google-chrome
    discord
    spotify
  ];

}
