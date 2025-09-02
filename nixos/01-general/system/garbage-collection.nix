{ config, pkgs, ... }:
{
  nix.gc = {
    automatic = true;
    persistent = true;
    # dates = "daily";
    options = "--delete-older-than 30d";
    dates = "17:00";                    # base time
    randomizedDelaySec = "15min";      # run somewhere between 18:00 and 18:15
    
  };
}
