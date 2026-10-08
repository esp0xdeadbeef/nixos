{ config, lib, ... }:
{
  # Container is DMZ-only: a single veth onto the guest's `vlan60` bridge
  # (neon site VLAN 60 = the dmz plane).  The base container-settings.nix
  # declares a veth per legacy cobalt VLAN; mkForce replaces that with the one
  # plane this host is exposed on.
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    veth0.hostBridge = "vlan60";
  };
}
