{ config, pkgs, ... }:
{
  virtualisation.qemu.networkingOptions = [
    "-nic bridge,br=vmbr0,model=virtio-net-pci,mac=BC:24:11:1D:0E:19,helper=/run/wrappers/bin/qemu-bridge-helper"
  ];
}
