{ pkgs, ... }:
{
  imports = [
    ./boot
    ./disks
    ./network
    ./qol
    ./hardware-configuration.nix
  ];
  boot.kexec.enable = true;

  environment.systemPackages = with pkgs; [
    kexec-tools
  ];
}
