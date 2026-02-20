{
  site-a = {
    fabric = {
      name = "single-wan";
      ulaPrefix = "fd42:dead:beef";
    };

    p2p-pool = {
      ipv4 = "10.10.0.0/24";
      ipv6 = "fd42:dead:beef:1000::/118";
    };

    nodes = {
      s-router-core.role = "core";
      s-router-policy.role = "policy";

      s-router-access-mgmt = {
        role = "access";
        networks = {
          ipv4 = "10.20.10.128/24";
          ipv6 = "fd42:dead:beef:10::/64";
          kind = "client";
        };
      };
    };

    links = [
      [
        "s-router-core"
        "s-router-policy"
      ]
      [
        "s-router-policy"
        "s-router-access-mgmt"
      ]
    ];
  };
  site-b = {
    p2p-pool = {
      ipv4 = "10.11.0.0/24";
      ipv6 = "fd42:dead:beef:1100::/118";
    };
    links = [
      [
        "s-router-core"
        "s-router-policy"
      ]
      [
        "s-router-policy"
        "s-router-access-mgmt"
      ]
    ];
    nodes = {
      s-router-core.role = "core";
      s-router-policy.role = "policy";

      s-router-access-mgmt = {
        role = "access";
        networks = {
          ipv4 = "10.30.10.0/24";
          ipv6 = "fd42:dead:beef:11::/64";
          kind = "client";
        };
      };
    };
  };
}
