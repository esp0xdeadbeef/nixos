{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."crypted" = {
    allowDiscards = true;
  };

  boot.initrd.clevis.enable = true;
  boot.initrd.clevis.useTang = true;
  boot.initrd.clevis.devices."crypted".secretFile = ./nvme0n1p1.jwe;

  boot.initrd.systemd.network.enable = true;
  boot.initrd.systemd.network.wait-online.enable = true;
  boot.initrd.systemd.network.wait-online.timeout = 30;

  boot.initrd.systemd.network.networks."10-eno4" = {
    matchConfig.Name = "eno4";
    networkConfig.Address = "192.168.1.98/24";
  };

  # dit is de ENIGE wijziging:
  boot.initrd.systemd.services."cryptsetup-clevis-crypted" = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };

    unitConfig = {
      StartLimitBurst = 10; # RETRY = 10
    };
  };

  boot.initrd.kernelModules = [
    "bnx2"
    "bnx2x"
    "ixgbe"
  ];
}
