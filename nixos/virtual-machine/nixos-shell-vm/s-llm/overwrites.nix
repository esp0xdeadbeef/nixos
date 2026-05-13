{ config, lib, ... }:
{
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    veth0.hostBridge = "vlan2";
  };
}
