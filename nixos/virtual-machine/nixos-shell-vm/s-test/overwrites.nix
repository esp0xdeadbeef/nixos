{ config, lib, ... }:
{
  #containers."${config.networking.hostName}-container".extraVeths = lib.mkForce {
  #  veth7.hostBridge = "vlan7";
  #};

}
