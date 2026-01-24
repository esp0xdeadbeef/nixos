{ config, pkgs, ... }:
{
  nix.gc = {
    automatic = true;
    persistent = true;
    dates = "*:0/15";
    options = "--delete-older-than 30d";
    randomizedDelaySec = "5min";
  };
}
