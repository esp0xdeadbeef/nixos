{
  deployment.host.s-router-upstream-selector = {
    uplink = {
      parent = "eth0";

      upstream-core = {
        vlan = 5;
        bridge = "br-upstream";
      };

      upstream-policy = {
        vlan = 200;
        bridge = "br-fabric";
      };
    };
  };

  fabric = {
    s-router-upstream-selector = {
      platform = "linux";
      ports = {
        core = {
          link = "p2p-s-router-core-wan-s-router-upstream-selector";
          vlan = 200;
        };

        policy = {
          link = "p2p-s-router-policy-s-router-upstream-selector";
          vlan = 201;
        };
      };
    };
  };
}
