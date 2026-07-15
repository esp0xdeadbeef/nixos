{ lib, ... }:

{
  containers.downstream-selector.config.systemd.network.networks."10-access-vlan3".routingPolicyRules =
    lib.mkBefore [
      {
        Family = "ipv4";
        IncomingInterface = "access-vlan3";
        Priority = 900;
        Table = 254;
        To = "192.168.1.0/24";
      }
    ];
}
