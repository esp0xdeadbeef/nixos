{ config
, lib
, pkgs
, ...
}:
{
  boot.initrd.luks.devices = lib.mkForce {
    root = {
      device = "/dev/disk/by-partlabel/disk-nvme0n1-luks";
      allowDiscards = true;
    };
  };
  swapDevices = lib.mkForce [ ];

  networking.useDHCP = lib.mkDefault true;

  system.stateVersion = "24.11";
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    btrfs-progs
    dosfstools
    e2fsprogs
    exfatprogs
    parted
    util-linux
  ];
}
