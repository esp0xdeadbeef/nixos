{
  domain = "lan.";

  # Physical interface names per node (no guessing, no hardcoding in modules)
  nodes = {
    "s-router-core-wan" = {
      ifs = {
        lan = "lan";
        wan = "wan";
      };
    };

    "s-router-policy-only" = {
      ifs = {
        lan = "lan";
      };
    };

    "s-router-legacy-edge" = {
      ifs = {
        lan = "lan";
      };
    };

    "s-router-access-110" = {
      ifs = {
        lan = "lan";
      };
    };
  };

  # Links are the truth. VLAN is merely a carrier attribute.
  links = {
    # --- Legacy L2 segment (ONLY where needed) ---
    legacy = {
      kind = "l2";
      carrier = "lan";
      vlanId = 1010;

      # Semantic identity (NOT a kernel ifname)
      name = "legacy-l2-1010";

      members = [
        "s-router-core-wan"
        "s-router-legacy-edge"
      ];

      # Optional L3 intent on this L2 (only applied where defined below)
      endpoints = {
        "s-router-core-wan" = {
          addr4 = "10.255.255.1/29";

          # “back routes” to legacy router
          routes4 = [
            {
              dst = "192.168.1.0/24";
              via4 = "10.255.255.3";
            }
            {
              dst = "192.168.2.0/24";
              via4 = "10.255.255.3";
            }
          ];
        };
      };
    };

    # --- Core ISP uplink adjacency: core-wan <-> policy-only ---
    core-edge-isp = {
      kind = "p2p";
      carrier = "lan";
      vlanId = 100;

      # Semantic identity (NOT a kernel ifname)
      name = "core-edge-isp";

      members = [
        "s-router-core-wan"
        "s-router-policy-only"
      ];

      # Explicit addressing. No RA. No DHCP on transit.
      endpoints = {
        "s-router-core-wan" = {
          addr4 = "10.255.0.0/31";
          addr6 = "fd42:dead:beef:ff00::0/127";

          # Route delegated prefix (read from file) to edge over this p2p
          route6FromPrefixFile = {
            prefixFile = "/run/secrets/subnet-ipv6";
            via6 = "fd42:dead:beef:ff00::1";
          };
        };

        "s-router-policy-only" = {
          addr4 = "10.255.0.1/31";
          addr6 = "fd42:dead:beef:ff00::1/127";
        };
      };
    };

    # --- Policy <-> Access example adjacency ---
    policy-access-110 = {
      kind = "p2p";
      carrier = "lan";
      vlanId = 110;

      # Semantic identity (NOT a kernel ifname)
      name = "policy-access-110";

      members = [
        "s-router-policy-only"
        "s-router-access-110"
      ];

      endpoints = {
        "s-router-policy-only" = {
          addr4 = "10.255.10.0/31";
          addr6 = "fd42:dead:beef:ff10::0/127";
        };

        "s-router-access-110" = {
          addr4 = "10.255.10.1/31";
          addr6 = "fd42:dead:beef:ff10::1/127";
        };
      };
    };
  };
}
