{ config, pkgs, ... }:
{
  networking.hostName = "l-x13s";
  nixos-x13s.enable = true;
  nixos-x13s.bluetoothMac = "E9:1C:3B:F0:FD:8C";
  nixos-x13s.wifiMac = "8c:fd:f0:1c:3b:0a";
  specialisation = {
    mainline.configuration.nixos-x13s.kernel = "mainline";
  };
  nixpkgs.config.allowUnfree = true;
  boot.initrd.luks.devices = {
    root = {
      device = "/dev/nvme0n1p2";
    };
  };
  fileSystems."/".device = "/dev/mapper/root";
  system.stateVersion = "24.11";
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [ util-linux ];
}
