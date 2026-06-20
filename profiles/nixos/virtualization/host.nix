{ profiles, ... }:
{
  imports = [
    profiles.nixos.virtualization.docker
    profiles.nixos.virtualization.libvirt
    profiles.nixos.virtualization.podman
    profiles.nixos.virtualization.lxc
  ];
}
