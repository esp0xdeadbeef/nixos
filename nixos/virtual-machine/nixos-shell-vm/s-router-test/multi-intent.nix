{
  esp0xdeadbeef.site-a = {
    pools = {
      p2p = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      loopback = {
        ipv4 = "10.19.0.0/24";
        ipv6 = "fd42:dead:beef:1900::/118";
      };
    };

    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
        {
          kind = "tenant";
          name = "admin";
          ipv4 = "10.20.15.0/24";
          ipv6 = "fd42:dead:beef:15::/64";
        }
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
      ];
    };

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];

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
      ];

      interfaceTags = {
        tenant-mgmt = "mgmt";
        tenant-admin = "admin";
        tenant-client = "client";
        external-isp-a = "isp-a";
        external-isp-b = "isp-b";
      };
    };

    topology = {
      nodes = {
        s-router-core-isp-a = {
          role = "core";

          uplinks = {
            isp-a = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-core-isp-b = {
          role = "core";

          uplinks = {
            isp-b = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };

        s-router-policy-only = {
          role = "policy";
        };

        s-router-downstream-selector = {
          role = "downstream-selector";
        };

        s-router-access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };

        s-router-access-admin = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "admin";
            }
          ];
        };

        s-router-access-client = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };
      };

      links = [
        [
          "s-router-core-isp-a"
          "s-router-upstream-selector"
        ]
        [
          "s-router-core-isp-b"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy-only"
        ]
        [
          "s-router-policy-only"
          "s-router-downstream-selector"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-client"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-admin"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access-mgmt"
        ]
      ];
    };
  };
}
