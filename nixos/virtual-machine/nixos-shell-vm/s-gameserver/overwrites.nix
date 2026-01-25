{ config, lib, ... }:
{
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
    veth2.hostBridge = "vlan2";
    veth7.hostBridge = "vlan7";
  };
}
