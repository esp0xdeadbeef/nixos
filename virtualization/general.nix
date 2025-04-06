{ config, pkgs, ... }:
{
  virtualisation.spiceUSBRedirection.enable = true;
  virtualisation.docker.enable = true;
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "deadbeef" ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];
}
