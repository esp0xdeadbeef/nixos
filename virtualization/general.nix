{ config, pkgs, ... }: {
virtualisation.spiceUSBRedirection.enable = true;
virtualisation.docker.enable = true;
programs.virt-manager.enable = true;
users.groups.libvirtd.members = [ "deadbeef" ];
}
