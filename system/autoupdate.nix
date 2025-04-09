{ config, pkgs, lib, ... }:
let
  hostname = builtins.readFile "/etc/hostname";  # Read the hostname dynamically
in {
  #############################
  # Auto update with dynamic hostname
  #############################
  system.autoUpgrade = {
    enable = true;
    flake = "github:esp0xdeadbeef/nixos#" + lib.strings.removeSuffix "\n" hostname;
    flags = [ "--impure" "--no-write-lock-file" ]; # Remove --no-write-lock-file and --upgrade
    dates = "9:00";
    randomizedDelaySec = "45min";
    operation = "boot";
    allowReboot = false;
  };
}

