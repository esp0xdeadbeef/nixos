{ config, pkgs, ... }:

{
  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices."crypted" = {
    device = "/dev/disk/by-uuid/d05a14b3-1b49-4dc1-884c-784d48569839";
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
    networkConfig.DHCP = "yes";
  };

  boot.initrd.kernelModules = [ "bnx2" "bnx2x" "ixgbe" ];
}

