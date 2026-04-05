{
  endpoints = {
    web01 = {
      ipv4 = [ "10.20.15.10" ];
      ipv6 = [ "fd42:dead:beef:15::10" ];
    };

    s-sigma = {
      ipv4 = [ "10.20.10.10" ];
      ipv6 = [ "fd42:dead:beef:10::10" ];
    };
  };

  deployment = {
    hosts = {
      lab-host = {
        uplinks = {
          uplink0 = {
            parent = "eno1";
            bridge = "br-uplink0";
            ipv4 = {
              method = "dhcp";
            };
            ipv6 = {
              method = "slaac";
            };
          };
        };
      };
    };
  };

  realization = {
    nodes = {
      esp0xdeadbeef-site-a-s-router-core-wan = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-core-wan";
        };
        ports = {
          upstream-selector = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };

          wan = {
            upstream = "uplink0";
            link = "wan";
            attach = {
              kind = "bridge";
              bridge = "br-uplink0";
            };
            interface = {
              name = "ens4";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-upstream-selector = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-upstream-selector";
        };
        ports = {
          core = {
            link = "p2p-s-router-core-wan-s-router-upstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };

          policy = {
            link = "p2p-s-router-policy-s-router-upstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens4";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-policy = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-policy";
        };
        ports = {
          upstream-selector = {
            link = "p2p-s-router-policy-s-router-upstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };

          downstream-selector = {
            link = "p2p-s-router-downstream-selector-s-router-policy";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens4";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-downstream-selector = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-downstream-selector";
        };
        ports = {
          policy = {
            link = "p2p-s-router-downstream-selector-s-router-policy";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };

          access-client = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens4";
            };
          };

          access-admin = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens5";
            };
          };

          access-mgmt = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens6";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-client = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-client";
        };
        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-client-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-admin = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-admin";
        };
        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-admin-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };
        };
      };

      esp0xdeadbeef-site-a-s-router-access-mgmt = {
        host = "lab-host";
        platform = "linux";
        logicalNode = {
          enterprise = "esp0xdeadbeef";
          site = "site-a";
          name = "s-router-access-mgmt";
        };
        ports = {
          transit-downstream-selector = {
            link = "p2p-s-router-access-mgmt-s-router-downstream-selector";
            attach = {
              kind = "direct";
            };
            interface = {
              name = "ens3";
            };
          };
        };
      };
    };
  };
}
