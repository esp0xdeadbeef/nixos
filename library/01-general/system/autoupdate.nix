{ config
, pkgs
, lib
, ...
}:

{
  system.autoUpgrade = {
    enable = true;
    flake = "github:esp0xdeadbeef/nixos#" + config.networking.hostName;
    flags = [
      "--accept-flake-config"
      "--impure"
      "--no-write-lock-file"
    ];
    dates = "4:30";
    randomizedDelaySec = "15min";
    operation = "boot";
    allowReboot = false;
  };

  systemd.services.nixos-upgrade = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "2h";
    };
  };
}
