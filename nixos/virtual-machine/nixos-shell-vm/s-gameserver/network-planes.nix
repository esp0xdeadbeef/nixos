{ config, lib, relativeRepo, pkgs, ... }:

let
  mkMgmt = import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix") {
    inherit lib pkgs;
  };
  mkBridge = import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix") {
    inherit lib pkgs;
  };
in
{
  # The gameserver is dual-homed on the neon 802.1Q trunk (l-envil's vmbr4,
  # the trunk s-router-neon terminates):
  #
  #   VLAN 20 `svc` -> the VM host's own network; DHCP on the vlan20 bridge.
  #                    Podman pulls its container images here, and
  #                    /persist-state (a block disk, never a 9p share) caches
  #                    them.  The container never sees this NIC.
  #   VLAN 60 `dmz` -> the exposed plane.  Only the container is attached, so
  #                    only the modelled public tuples (25565/25566 tcp,
  #                    2456-2458 udp) reach it.
  #
  # Pull traffic stays off the dmz, and the dmz has no WAN egress (it is not in
  # the intent's `allowTenantToWan` set), so the exposed container cannot reach
  # the internet even though the VM host fetched the images.
  #
  # VLAN ids come from the neon site inventory transitBridges map
  # (prod-network/testing/inventory-neon.nix): svc = 20, dmz = 60.
  #
  # The base host-config/network.nix set (2..9, 1010) stays; its bridges are
  # simply unused here, the same way s-nebula keeps them.
  imports = [
    (mkMgmt "eth0" 20 { bridge = "vlan20"; })
    (mkBridge "eth0" 60 { bridge = "vlan60"; })
  ];
}
