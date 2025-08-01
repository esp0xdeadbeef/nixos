{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # virtualization:
    podman
    docker
    lxc
    libvirt
    virt-manager
    virt-viewer
    spice
    spice-gtk
    spice-protocol
    win-virtio
    win-spice
    qemu
    # kind creates and manages local Kubernetes clusters using Docker container 'nodes'
    kind

    # i need bindfs always when i'm using lxc- maybe also with podman / docker.
    bindfs
  ];
}
