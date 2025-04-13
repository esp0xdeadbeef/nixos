{ config, pkgs, ... }:
{

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    # firefox
    brave
    chromium
  ];
}
