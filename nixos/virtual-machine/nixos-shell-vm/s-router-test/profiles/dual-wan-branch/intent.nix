let
  base = import ../dual-wan/intent.nix;

  siteA = base.esp0xdeadbeef.site-a;
in
base
// {
  esp0xdeadbeef.site-a =
    siteA
    // {
      ownership = {
        prefixes =
          siteA.ownership.prefixes
          ++ [
            {
              kind = "tenant";
              name = "dmz";
              ipv4 = "10.20.30.0/24";
              ipv6 = "fd42:dead:beef:30::/64";
            }
          ];

        endpoints = [
          {
            kind = "host";
            name = "nebula01";
            tenant = "dmz";
          }
        ];
      };

      communicationContract = {
        trafficTypes = [
          {
            name = "nebula";
            match = [
              {
                proto = "tcp";
                dports = [ 4242 ];
                family = "any";
              }
              {
                proto = "udp";
                dports = [ 4242 ];
                family = "any";
              }
            ];
          }
        ];

        services = [
          {
            name = "dmz-nebula";
            trafficType = "nebula";
            providers = [ "nebula01" ];
          }
        ];

        relations = [
          {
            id = "allow-mgmt-internal";
            priority = 10;
            from = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            to = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client"
                "dmz"
              ];
            };
            trafficType = "any";
            action = "allow";
          }

          {
            id = "allow-tenants-to-uplinks";
            priority = 100;
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client"
                "dmz"
              ];
            };
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "any";
            action = "allow";
          }

          {
            id = "allow-core-tenants-to-east-west";
            priority = 110;
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client"
              ];
            };
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "any";
            action = "allow";
          }

          {
            id = "allow-wan-to-dmz-nebula";
            priority = 120;
            from = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            to = {
              kind = "service";
              name = "dmz-nebula";
            };
            trafficType = "nebula";
            action = "allow";
          }
        ];

        interfaceTags = {
          tenant-mgmt = "mgmt";
          tenant-admin = "admin";
          tenant-client = "client";
          tenant-dmz = "dmz";
          external-isp-a = "isp-a";
          external-isp-b = "isp-b";
          external-east-west = "east-west";
          service-dmz-nebula = "dmz-nebula";
        };
      };

      transport.overlays = [
        {
          name = "east-west";
          peerSite = "espbranch.site-b";
          terminateOn = "s-router-core-isp-b";
          mustTraverse = [ "policy" ];
        }
      ];

      topology =
        siteA.topology
        // {
          nodes =
            siteA.topology.nodes
            // {
              s-router-access-dmz = {
                role = "access";
                attachments = [
                  {
                    kind = "tenant";
                    name = "dmz";
                  }
                ];
              };
            };

          links =
            siteA.topology.links
            ++ [
              [
                "s-router-downstream-selector"
                "s-router-access-dmz"
              ]
            ];
        };
    };

  espbranch.site-b = {
    pools = {
      p2p = {
        ipv4 = "10.50.0.0/24";
        ipv6 = "fd42:dead:feed:1000::/118";
      };

      loopback = {
        ipv4 = "10.59.0.0/24";
        ipv6 = "fd42:dead:feed:1900::/118";
      };
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "branch";
        ipv4 = "10.60.10.0/24";
        ipv6 = "fd42:dead:feed:10::/64";
      }
    ];

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];

      relations = [
        {
          id = "allow-branch-to-wan";
          priority = 100;
          from = {
            kind = "tenant-set";
            members = [ "branch" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-branch-to-east-west";
          priority = 110;
          from = {
            kind = "tenant-set";
            members = [ "branch" ];
          };
          to = {
            kind = "external";
            name = "east-west";
          };
          trafficType = "any";
          action = "allow";
        }
      ];

      interfaceTags = {
        tenant-branch = "branch";
        external-wan = "wan";
        external-east-west = "east-west";
      };
    };

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "esp0xdeadbeef.site-a";
        terminateOn = "b-router-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        b-router-core = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        b-router-upstream-selector.role = "upstream-selector";
        b-router-policy.role = "policy";
        b-router-downstream-selector.role = "downstream-selector";

        b-router-access-branch = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "branch";
            }
          ];
        };
      };

      links = [
        [
          "b-router-core"
          "b-router-upstream-selector"
        ]
        [
          "b-router-upstream-selector"
          "b-router-policy"
        ]
        [
          "b-router-policy"
          "b-router-downstream-selector"
        ]
        [
          "b-router-downstream-selector"
          "b-router-access-branch"
        ]
      ];
    };
  };
}
