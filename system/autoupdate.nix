{ config, pkgs, lib, ... }:
let
  hostname = builtins.readFile "/etc/hostname";  # Read the hostname dynamically
in {
  #############################
  # Auto update with dynamic hostname
  #############################
  system.autoUpgrade = {
    enable = true;
    flake = "github:esp0xdeadbeef/nixos#" + lib.strings.removeSuffix "\n" hostname;  # Use the hostname
    flags = [ "--impure" ];
    dates = "Mon 9:00";
    randomizedDelaySec = "45min";
    operation = "switch";  # Avoid switching to a new kernel immediately
    allowReboot = false;   # Prevent automatic reboots
  };
}

