{ config, pkgs, ... }:
{
  nixos-x13s.enable = true;
  nixos-x13s.bluetoothMac = "E9:1C:3B:F0:FD:8C";
  nixos-x13s.wifiMac = "8c:fd:f0:1c:3b:0a";
  specialisation = {
    mainline.configuration.nixos-x13s.kernel = "mainline";
  };
  boot.initrd.luks.devices = {
    root = {
      device = "/dev/nvme0n1p2";
    };
  };
  fileSystems."/".device = "/dev/mapper/root";

  fileSystems."/boot" = {
    device = "/dev/nvme0n1p1";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  system.stateVersion = "24.11";
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [ util-linux ];
}
