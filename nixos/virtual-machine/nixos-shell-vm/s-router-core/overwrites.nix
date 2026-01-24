{config, lib, ...}:
{
  containers."${config.networking.hostName}-container".extraVeths = lib.mkForce { veth-game.hostBridge = "vlan2"; };
}
