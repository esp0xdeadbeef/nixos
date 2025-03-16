{ config, pkgs, ... }: {

 #############################
 # Auto update
 #############################
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos"; # Explicitly set the flake path
    flags = [
      "--impure"
      "--flake" "/etc/nixos#nixos"
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
}

