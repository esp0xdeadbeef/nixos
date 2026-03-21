{
  config,
  pkgs,
  lib,
  ...
}:

{
  system.autoUpgrade = {
    enable = true;
    flake = "github:esp0xdeadbeef/nixos#" + config.networking.hostName;
    flags = [
      "--impure"
      "--no-write-lock-file"
    ];
    dates = "4:30";
    randomizedDelaySec = "15min";
    operation = "boot";
    allowReboot = false;
  };
}
