{ lib
, pkgs
, relativeRepo
, ...
}:

let
  # Keep the current attachment local to s-llm-inference: moving it off VLAN 2
  # later should only require changing this module.
  vlanId = 2;
  bridge = "vlan${toString vlanId}";
  mkMgmt = import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix") {
    inherit lib pkgs;
  };
in
{
  imports = [
    (mkMgmt "eth0" vlanId { inherit bridge; })
  ];

  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic none"
    "-nic bridge,br=vmbr4,mac=52:54:00:11:4a:34,model=virtio-net-pci"
  ];

  networking.firewall.interfaces.${bridge}.allowedTCPPorts = [
    11434 # Ollama directly in the VM.
    11435 # Ollama in the OCI container.
  ];
}
