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
              name = "client2";
              ipv4 = "10.20.40.0/24";
              ipv6 = "fd42:dead:beef:40::/64";
            }
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
            name = "dns";
            match = [
              {
                proto = "udp";
                dports = [ 53 ];
                family = "any";
              }
              {
                proto = "tcp";
                dports = [ 53 ];
                family = "any";
              }
            ];
          }

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
            name = "site-dns-mgmt";
            trafficType = "dns";
            providers = [ "site-dns-mgmt" ];
          }

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
                "client2"
                "dmz"
              ];
            };
            trafficType = "any";
            action = "allow";
          }

          {
            id = "allow-sitea-tenants-to-mgmt-dns";
            priority = 15;
            from = {
              kind = "tenant-set";
              members = [
                "admin"
                "client"
                "client2"
                "dmz"
              ];
            };
            to = {
              kind = "service";
              name = "site-dns-mgmt";
            };
            trafficType = "dns";
            action = "allow";
          }

          {
            id = "allow-mgmt-dns-to-uplinks";
            priority = 16;
            from = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "dns";
            action = "allow";
          }

          {
            id = "deny-sitea-dns-to-uplinks";
            priority = 20;
            from = {
              kind = "tenant-set";
              members = [
                "mgmt"
                "admin"
                "client"
                "client2"
              ];
            };
            to = {
              kind = "external";
              uplinks = [
                "isp-a"
                "isp-b"
              ];
            };
            trafficType = "dns";
            action = "deny";
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
                "client2"
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
                "client2"
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
            id = "allow-east-west-to-sitea-mgmt-dns";
            priority = 115;
            from = {
              kind = "external";
              name = "east-west";
            };
            to = {
              kind = "service";
              name = "site-dns-mgmt";
            };
            trafficType = "dns";
            action = "allow";
          }

          {
            id = "allow-sitea-mgmt-to-sitec-storage";
            priority = 116;
            from = {
              kind = "tenant-set";
              members = [ "mgmt" ];
            };
            to = {
              kind = "external";
              name = "site-c-storage";
            };
            trafficType = "any";
            action = "allow";
          }

          {
            id = "allow-sitec-storage-to-sitea-mgmt";
            priority = 117;
            from = {
              kind = "external";
              name = "site-c-storage";
            };
            to = {
              kind = "tenant-set";
              members = [ "mgmt" ];
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
          tenant-client2 = "client2";
          tenant-dmz = "dmz";
          external-isp-a = "isp-a";
          external-isp-b = "isp-b";
          external-east-west = "east-west";
          external-site-c-storage = "site-c-storage";
          service-site-dns-mgmt = "site-dns-mgmt";
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
        {
          name = "site-c-storage";
          peerSite = "esp0xdeadbeef.site-c";
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

              s-router-access-client2 = {
                role = "access";
                attachments = [
                  {
                    kind = "tenant";
                    name = "client2";
                  }
                ];
              };
            };

          links =
            siteA.topology.links
            ++ [
              [
                "s-router-downstream-selector"
                "s-router-access-client2"
              ]
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
      {
        kind = "tenant";
        name = "hostile";
        ipv4 = "10.70.10.0/24";
        ipv6 = "fd42:dead:feed:70::/64";
      }
    ];

    communicationContract = {
      trafficTypes = [
        {
          name = "dns";
          match = [
            {
              proto = "udp";
              dports = [ 53 ];
              family = "any";
            }
            {
              proto = "tcp";
              dports = [ 53 ];
              family = "any";
            }
          ];
        }
      ];
      services = [ ];

      relations = [
        {
          id = "deny-branch-dns-to-wan";
          priority = 90;
          from = {
            kind = "tenant-set";
            members = [ "branch" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "dns";
          action = "deny";
        }

        {
          id = "deny-hostile-dns-to-wan";
          priority = 91;
          from = {
            kind = "tenant-set";
            members = [ "hostile" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "dns";
          action = "deny";
        }

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
          id = "allow-hostile-to-wan";
          priority = 101;
          from = {
            kind = "tenant-set";
            members = [ "hostile" ];
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

        {
          id = "allow-east-west-to-branch";
          priority = 120;
          from = {
            kind = "external";
            name = "east-west";
          };
          to = {
            kind = "tenant-set";
            members = [ "branch" ];
          };
          trafficType = "any";
          action = "allow";
        }
      ];

      interfaceTags = {
        tenant-branch = "branch";
        tenant-hostile = "hostile";
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

        b-router-access-hostile = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "hostile";
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
        [
          "b-router-downstream-selector"
          "b-router-access-hostile"
        ]
      ];
    };
  };

  esp0xdeadbeef.site-c = {
    pools = {
      p2p = {
        ipv4 = "10.80.0.0/24";
        ipv6 = "fd42:dead:cafe:1000::/118";
      };

      loopback = {
        ipv4 = "10.89.0.0/24";
        ipv6 = "fd42:dead:cafe:1900::/118";
      };
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.90.10.0/24";
        ipv6 = "fd42:dead:cafe:10::/64";
      }
      {
        kind = "tenant";
        name = "home-users";
        ipv4 = "10.90.20.0/24";
        ipv6 = "fd42:dead:cafe:20::/64";
      }
      {
        kind = "tenant";
        name = "printer";
        ipv4 = "10.90.30.0/29";
        ipv6 = "fd42:dead:cafe:30::/64";
      }
      {
        kind = "tenant";
        name = "nas";
        ipv4 = "10.90.40.0/29";
        ipv6 = "fd42:dead:cafe:40::/64";
      }
      {
        kind = "tenant";
        name = "streaming";
        ipv4 = "10.90.50.0/29";
        ipv6 = "fd42:dead:cafe:50::/64";
      }
      {
        kind = "tenant";
        name = "iot";
        ipv4 = "10.90.60.0/24";
        ipv6 = "fd42:dead:cafe:60::/64";
      }
    ];

    communicationContract = {
      trafficTypes = [
        {
          name = "dns";
          match = [
            {
              proto = "udp";
              dports = [ 53 ];
              family = "any";
            }
            {
              proto = "tcp";
              dports = [ 53 ];
              family = "any";
            }
          ];
        }
      ];

      services = [
        {
          name = "sitec-dns-mgmt";
          trafficType = "dns";
          providers = [ "sitec-dns-mgmt" ];
        }
      ];

      relations = [
        {
          id = "allow-sitec-mgmt-internal";
          priority = 10;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "home-users"
              "printer"
              "nas"
              "streaming"
              "iot"
            ];
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-home-to-local-services";
          priority = 20;
          from = {
            kind = "tenant-set";
            members = [ "home-users" ];
          };
          to = {
            kind = "tenant-set";
            members = [
              "printer"
              "nas"
              "streaming"
            ];
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-tenants-to-mgmt-dns";
          priority = 30;
          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "home-users"
              "printer"
              "nas"
              "streaming"
              "iot"
            ];
          };
          to = {
            kind = "service";
            name = "sitec-dns-mgmt";
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "allow-sitec-mgmt-dns-to-wan";
          priority = 31;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "deny-sitec-printer-dns-to-wan";
          priority = 40;
          from = {
            kind = "tenant-set";
            members = [ "printer" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "deny-sitec-nas-dns-to-wan";
          priority = 41;
          from = {
            kind = "tenant-set";
            members = [ "nas" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-sitec-home-to-wan";
          priority = 100;
          from = {
            kind = "tenant-set";
            members = [ "home-users" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-streaming-to-wan";
          priority = 101;
          from = {
            kind = "tenant-set";
            members = [ "streaming" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-iot-to-wan";
          priority = 102;
          from = {
            kind = "tenant-set";
            members = [ "iot" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-mgmt-to-wan";
          priority = 103;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "deny-sitec-printer-to-wan";
          priority = 110;
          from = {
            kind = "tenant-set";
            members = [ "printer" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "deny-sitec-nas-to-wan";
          priority = 111;
          from = {
            kind = "tenant-set";
            members = [ "nas" ];
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "deny";
        }
        {
          id = "allow-sitec-printer-to-storage-overlay";
          priority = 120;
          from = {
            kind = "tenant-set";
            members = [ "printer" ];
          };
          to = {
            kind = "external";
            name = "site-c-storage";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-nas-to-storage-overlay";
          priority = 121;
          from = {
            kind = "tenant-set";
            members = [ "nas" ];
          };
          to = {
            kind = "external";
            name = "site-c-storage";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-mgmt-to-storage-overlay";
          priority = 122;
          from = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          to = {
            kind = "external";
            name = "site-c-storage";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-sitec-storage-overlay-to-mgmt";
          priority = 123;
          from = {
            kind = "external";
            name = "site-c-storage";
          };
          to = {
            kind = "tenant-set";
            members = [ "mgmt" ];
          };
          trafficType = "any";
          action = "allow";
        }
      ];

      interfaceTags = {
        tenant-mgmt = "mgmt";
        tenant-home-users = "home-users";
        tenant-streaming = "streaming";
        tenant-printer = "printer";
        tenant-nas = "nas";
        tenant-iot = "iot";
        external-wan = "wan";
        external-site-c-storage = "site-c-storage";
        service-sitec-dns-mgmt = "sitec-dns-mgmt";
      };
    };

    transport.overlays = [
      {
        name = "site-c-storage";
        peerSite = "esp0xdeadbeef.site-a";
        terminateOn = "c-router-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        c-router-core = {
          role = "core";

          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        c-router-upstream-selector.role = "upstream-selector";
        c-router-policy.role = "policy";
        c-router-downstream-selector.role = "downstream-selector";

        c-router-access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };

        c-router-access-media = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "home-users";
            }
            {
              kind = "tenant";
              name = "streaming";
            }
          ];
        };

        c-router-access-printer = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "printer";
            }
          ];
        };

        c-router-access-nas = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "nas";
            }
          ];
        };

        c-router-access-iot = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "iot";
            }
          ];
        };
      };

      links = [
        [
          "c-router-core"
          "c-router-upstream-selector"
        ]
        [
          "c-router-upstream-selector"
          "c-router-policy"
        ]
        [
          "c-router-policy"
          "c-router-downstream-selector"
        ]
        [
          "c-router-downstream-selector"
          "c-router-access-mgmt"
        ]
        [
          "c-router-downstream-selector"
          "c-router-access-media"
        ]
        [
          "c-router-downstream-selector"
          "c-router-access-printer"
        ]
        [
          "c-router-downstream-selector"
          "c-router-access-nas"
        ]
        [
          "c-router-downstream-selector"
          "c-router-access-iot"
        ]
      ];
    };
  };
}
