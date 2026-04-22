let
  base = import ../dual-wan/bgp-inventory.nix;

  publicDns4 = [
    "1.1.1.1"
    "9.9.9.9"
  ];

  publicDns6 = [
    "2606:4700:4700::1111"
    "2620:fe::fe"
  ];

  dmzDns = {
    listen = [
      "10.20.30.1"
      "fd42:dead:beef:30::1"
    ];
    allowFrom = [
      "10.20.30.0/24"
      "fd42:dead:beef:30::/64"
    ];
    forwarders = publicDns4 ++ publicDns6;
    advertised = {
      dnsServers = publicDns4;
      rdnss = publicDns6;
    };
  };

  branchCoreDns = {
    listen = [
      "10.59.0.3"
      "fd42:dead:feed:1900::3"
    ];
    allowFrom = [
      "10.60.10.0/24"
      "fd42:dead:feed:10::/64"
    ];
    forwarders = publicDns4 ++ publicDns6;
    advertised = {
      dnsServers = publicDns4;
      rdnss = publicDns6;
    };
  };

  host = base.deployment.hosts.s-router-test;

  siteANodes = base.realization.nodes;
in
base
// {
  endpoints =
    (base.endpoints or { })
    // {
      nebula01 = {
        ipv4 = [ "10.20.30.10" ];
        ipv6 = [ "fd42:dead:beef:30::10" ];
      };
    };

  controlPlane =
    base.controlPlane
    // {
      sites =
        base.controlPlane.sites
        // {
          esp0xdeadbeef =
            base.controlPlane.sites.esp0xdeadbeef
            // {
              "site-a" =
                base.controlPlane.sites.esp0xdeadbeef."site-a"
                // {
                  overlays.east-west = {
                    provider = "nebula";
                    ipam = {
                      ipv4.prefix = "100.96.10.0/24";
                      ipv6.prefix = "fd42:dead:beef:ee::/64";
                      nodes.s-router-core-isp-b = {
                        addr4 = "100.96.10.1/32";
                        addr6 = "fd42:dead:beef:ee::1/128";
                      };
                    };
                    nebula = {
                      role = "core-client";
                      lighthouse = {
                        endpoint = "nebula01";
                        port = 4242;
                      };
                    };
                  };
                };
            };

          espbranch = {
            "site-b" = {
              routing = {
                mode = "bgp";
                bgp = {
                  asn = 65100;
                  topology = "policy-rr";
                };
              };

              overlays.east-west = {
                provider = "nebula";
                ipam = {
                  ipv4.prefix = "100.96.10.0/24";
                  ipv6.prefix = "fd42:dead:beef:ee::/64";
                  nodes.b-router-core = {
                    addr4 = "100.96.10.2/32";
                    addr6 = "fd42:dead:beef:ee::2/128";
                  };
                };
                nebula = {
                  role = "core-client";
                  lighthouse = {
                    endpoint = "nebula01";
                    port = 4242;
                  };
                };
              };
            };
          };
        };
    };

  deployment =
    base.deployment
    // {
      hosts =
        base.deployment.hosts
        // {
          s-router-test =
            host
            // {
              bridgeNetworks =
                host.bridgeNetworks
                // {
                  br-site-a-policy-upstream-access-admin-east-west = { };
                  br-site-a-policy-upstream-access-client-east-west = { };
                  br-site-a-policy-upstream-access-mgmt-east-west = { };
                  br-site-a-policy-upstream-access-dmz-isp-a = { };
                  br-site-a-policy-upstream-access-dmz-isp-b = { };
                  br-site-a-downstream-policy-access-dmz = { };
                  br-site-a-downstream-dmz = { };
                  dmz = { };

                  br-site-b-core-upstream = { };
                  br-site-b-policy-upstream-access-branch-east-west = { };
                  br-site-b-policy-upstream-access-branch = { };
                  br-site-b-downstream-policy-access-branch = { };
                  br-site-b-downstream-branch = { };
                  branch = { };
                };
            };
        };
    };

  realization = {
    nodes =
      siteANodes
      // {
        esp0xdeadbeef-site-a-s-router-access-dmz = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "esp0xdeadbeef";
            site = "site-a";
            name = "s-router-access-dmz";
          };

          containers.default.runtimeName = "s-router-access-dmz";
          services.dns = dmzDns;

          ports = {
            transit-downstream-selector = {
              link = "p2p-s-router-access-dmz-s-router-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-a-downstream-dmz";
              };
              interface.name = "transit";
            };

            tenant-dmz = {
              logicalInterface = "tenant-dmz";
              attach = {
                kind = "bridge";
                bridge = "dmz";
              };
              interface = {
                name = "tenant-dmz";
                addr4 = "10.20.30.1/24";
                addr6 = "fd42:dead:beef:30::1/64";
              };
            };
          };

          advertisements = {
            dhcp4.tenant-dmz = {
              interface = "tenant-dmz";
              id = "dmz";
              subnet = "10.20.30.0/24";
              pool = {
                start = "10.20.30.100";
                end = "10.20.30.200";
              };
              router = "10.20.30.1";
              dnsServers = dmzDns.advertised.dnsServers;
              domain = "lan.";
            };

            ipv6Ra.tenant-dmz = {
              interface = "tenant-dmz";
              prefixes = [ "fd42:dead:beef:30::/64" ];
              rdnss = dmzDns.advertised.rdnss;
              dnssl = [ "lan." ];
            };
          };
        };

        esp0xdeadbeef-site-a-s-router-downstream-selector =
          siteANodes.esp0xdeadbeef-site-a-s-router-downstream-selector
          // {
            ports =
              siteANodes.esp0xdeadbeef-site-a-s-router-downstream-selector.ports
              // {
                policy-dmz = {
                  link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-dmz";
                  };
                  interface.name = "policy-dmz";
                };

                access-dmz = {
                  link = "p2p-s-router-access-dmz-s-router-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-dmz";
                  };
                  interface.name = "access-dmz";
                };
              };
          };

        esp0xdeadbeef-site-a-s-router-policy =
          siteANodes.esp0xdeadbeef-site-a-s-router-policy
          // {
            ports =
              siteANodes.esp0xdeadbeef-site-a-s-router-policy.ports
              // {
                upstream-admin-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-admin-east-west";
                  };
                  interface.name = "up-adm-ew";
                };

                upstream-client-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client-east-west";
                  };
                  interface.name = "up-cli-ew";
                };

                upstream-mgmt-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
                  };
                  interface.name = "up-mgt-ew";
                };

                upstream-dmz-isp-a = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-dmz--uplink-isp-a";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-dmz-isp-a";
                  };
                  interface.name = "up-dmz-a";
                };

                upstream-dmz-isp-b = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-dmz--uplink-isp-b";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-dmz-isp-b";
                  };
                  interface.name = "up-dmz-b";
                };

                downstream-dmz = {
                  link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-dmz";
                  };
                  interface.name = "downstream-dmz";
                };
              };
          };

        esp0xdeadbeef-site-a-s-router-upstream-selector =
          siteANodes.esp0xdeadbeef-site-a-s-router-upstream-selector
          // {
            ports =
              siteANodes.esp0xdeadbeef-site-a-s-router-upstream-selector.ports
              // {
                policy-admin-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-admin-east-west";
                  };
                  interface.name = "pol-adm-ew";
                };

                policy-client-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client-east-west";
                  };
                  interface.name = "pol-cli-ew";
                };

                policy-mgmt-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
                  };
                  interface.name = "pol-mgt-ew";
                };

                policy-dmz-isp-a = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-dmz--uplink-isp-a";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-dmz-isp-a";
                  };
                  interface.name = "pol-dmz-a";
                };

                policy-dmz-isp-b = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-dmz--uplink-isp-b";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-dmz-isp-b";
                  };
                  interface.name = "pol-dmz-b";
                };
              };
          };

        espbranch-site-b-b-router-core = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-core";
          };

          containers.default.runtimeName = "b-router-core";
          services.dns = branchCoreDns;

          ports = {
            upstream-selector = {
              link = "p2p-b-router-core-b-router-upstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-core-upstream";
              };
              interface.name = "upstream";
            };

            wan = {
              uplink = "wan";
              external = true;
              attach = {
                kind = "bridge";
                bridge = "br-uplink1";
              };
              interface.name = "wan";
            };
          };
        };

        espbranch-site-b-b-router-access-branch = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-access-branch";
          };

          containers.default.runtimeName = "b-router-access-branch";

          ports = {
            transit-downstream-selector = {
              link = "p2p-b-router-access-branch-b-router-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-branch";
              };
              interface.name = "transit";
            };

            tenant-branch = {
              logicalInterface = "tenant-branch";
              attach = {
                kind = "bridge";
                bridge = "branch";
              };
              interface = {
                name = "tenant-branch";
                addr4 = "10.60.10.1/24";
                addr6 = "fd42:dead:feed:10::1/64";
              };
            };
          };

          advertisements = {
            dhcp4.tenant-branch = {
              interface = "tenant-branch";
              id = "branch";
              subnet = "10.60.10.0/24";
              pool = {
                start = "10.60.10.100";
                end = "10.60.10.200";
              };
              router = "10.60.10.1";
              dnsServers = publicDns4;
              domain = "lan.";
            };

            ipv6Ra.tenant-branch = {
              interface = "tenant-branch";
              prefixes = [ "fd42:dead:feed:10::/64" ];
              rdnss = publicDns6;
              dnssl = [ "lan." ];
            };
          };
        };

        espbranch-site-b-b-router-downstream-selector = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-downstream-selector";
          };

          containers.default.runtimeName = "b-router-downstream-selector";

          ports = {
            policy-branch = {
              link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-branch";
              };
              interface.name = "policy-branch";
            };

            access-branch = {
              link = "p2p-b-router-access-branch-b-router-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-branch";
              };
              interface.name = "access-branch";
            };
          };
        };

        espbranch-site-b-b-router-policy = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-policy";
          };

          containers.default.runtimeName = "b-router-policy";

          ports = {
            upstream-branch-east-west = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch-east-west";
              };
              interface.name = "up-branch-ew";
            };

            upstream-branch = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch";
              };
              interface.name = "upstream-branch";
            };

            downstream-branch = {
              link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-branch";
              };
              interface.name = "downstream-branch";
            };
          };
        };

        espbranch-site-b-b-router-upstream-selector = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-upstream-selector";
          };

          containers.default.runtimeName = "b-router-upstream-selector";

          ports = {
            core = {
              link = "p2p-b-router-core-b-router-upstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-core-upstream";
              };
              interface.name = "core";
            };

            policy-branch-east-west = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch-east-west";
              };
              interface.name = "pol-branch-ew";
            };

            policy-branch = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch";
              };
              interface.name = "policy-branch";
            };
          };
        };
      };
  };
}
