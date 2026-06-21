{ config
, lib
, pkgs
, ...
}:
{
  boot.initrd.luks.devices = {
    root = {
      keyFile = lib.mkForce null;
    };
    cryptswap = {
      keyFile = lib.mkForce null;
    };
  };

  swapDevices = [
    {
      device = "/dev/mapper/cryptswap";
    }
  ];

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
