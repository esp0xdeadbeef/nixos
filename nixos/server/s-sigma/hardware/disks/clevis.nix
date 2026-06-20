{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  # s-sigma is bare metal without TPM. Disk unlock is handled by Clevis/Tang
  # over initrd networking, so disable systemd's TPM wait path explicitly.
  boot.initrd.systemd.tpm2.enable = false;
  boot.kernelParams = [ "systemd.tpm2_wait=0" ];
  systemd.tpm2.enable = false;

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

  # Be conservative during boot: initrd networking or Tang may be a little late.
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
