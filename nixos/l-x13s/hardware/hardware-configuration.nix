{ config, pkgs, ... }:
{
  
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
