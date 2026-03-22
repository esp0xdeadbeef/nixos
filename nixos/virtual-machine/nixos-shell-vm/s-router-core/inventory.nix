# ./inventory.nix
{
  deployment.host.s-router-core = {
    uplink = {
      parent = "eth0";

      management = {
        vlan = 2;
        bridge = "vlan2";
        addressing = {
          ipv4.mode = "dhcp";
          ipv6.mode = "disabled";
        };
      };

      wan = {
        vlan = 5;
        bridge = "br-upstream";
      };

      fabric = {
        vlan = 200;
        bridge = "br-fabric";
      };
    };
  };

  fabric = { };
}
