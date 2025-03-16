{ config, pkgs, ... }: {

 #############################
 # Auto update
 #############################
  system.autoUpgrade = {
    enable = true;
    flake = "github:esp0xdeadbeef/nixos#l-werk"; # Explicitly set the flake path
    flags = [
      "--impure"
      #"--flake" # "/etc/nixos#nixos"
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };
}

