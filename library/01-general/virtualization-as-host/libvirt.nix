{ config, lib, pkgs, ... }:
{
  users.users.deadbeef = {
    extraGroups = [ "libvirtd" ];
  };

  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };
}
