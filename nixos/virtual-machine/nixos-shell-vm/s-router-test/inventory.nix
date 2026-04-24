let
  base = import ./profiles/dual-wan/bgp-inventory.nix;

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
      dnsServers = [ "router-self" ];
      rdnss = [ "router-self" ];
    };
  };

  branchAccessDns = {
    listen = [
      "10.60.10.1"
      "fd42:dead:feed:10::1"
    ];
    allowFrom = [
      "10.60.10.0/24"
      "fd42:dead:feed:10::/64"
    ];
    forwarders = [
      "10.20.10.1"
      "fd42:dead:beef:10::1"
    ];
    advertised = {
      dnsServers = [ "router-self" ];
      rdnss = [ "router-self" ];
    };
  };

  hostileAccessDns = {
    listen = [
      "10.70.10.1"
      "fd42:dead:feed:70::1"
    ];
    allowFrom = [
      "10.70.10.0/24"
      "fd42:dead:feed:70::/64"
    ];
    forwarders = [
      "10.20.10.1"
      "fd42:dead:beef:10::1"
    ];
    advertised = {
      dnsServers = [ "router-self" ];
      rdnss = [ "router-self" ];
    };
  };

  policyDerivedDns = dnsAttrs: builtins.removeAttrs dnsAttrs [ "forwarders" "upstreams" ];

  overrideAdvertisedRouterSelf =
    inherited: tenantKey:
    inherited
    // {
      dhcp4 =
        (inherited.dhcp4 or { })
        // {
          ${tenantKey} =
            inherited.dhcp4.${tenantKey}
            // {
              dnsServers = [ "router-self" ];
            };
        };
      ipv6Ra =
        (inherited.ipv6Ra or { })
        // {
          ${tenantKey} =
            inherited.ipv6Ra.${tenantKey}
            // {
              rdnss = [ "router-self" ];
            };
        };
    };

  host = base.deployment.hosts.s-router-test;

  siteANodes = base.realization.nodes;

  siteC =
    let
      siteCBuilder =
        {
          base,
          publicDns4,
          publicDns6,
          policyDerivedDns,
        }:

        let
          sitecLocalZones = [
            {
              name = "printer.";
              type = "static";
            }
            {
              name = "home-users.";
              type = "static";
            }
            {
              name = "mgmt.";
              type = "static";
            }
            {
              name = "nas.";
              type = "static";
            }
          ];

          sitecLocalRecords = [
            {
              name = "test-machine-01.printer.";
              a = [ "10.90.30.2" ];
              aaaa = [ "fd42:dead:cafe:30::10" ];
            }
            {
              name = "home-user-01.home-users.";
              a = [ "10.90.20.10" ];
              aaaa = [ "fd42:dead:cafe:20::10" ];
            }
            {
              name = "sigma-site-c.mgmt.";
              a = [ "10.90.10.10" ];
              aaaa = [ "fd42:dead:cafe:10::10" ];
            }
            {
              name = "nas-node-01.nas.";
              a = [ "10.90.40.2" ];
              aaaa = [ "fd42:dead:cafe:40::10" ];
            }
          ];

          sitecMgmtDns = {
            listen = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
            allowFrom = [
              "10.90.10.0/24"
              "fd42:dead:cafe:10::/64"
              "10.90.20.0/24"
              "fd42:dead:cafe:20::/64"
              "10.90.30.0/29"
              "fd42:dead:cafe:30::/64"
              "10.90.40.0/29"
              "fd42:dead:cafe:40::/64"
              "10.90.50.0/29"
              "fd42:dead:cafe:50::/64"
              "10.90.60.0/24"
              "fd42:dead:cafe:60::/64"
            ];
            forwarders = publicDns4 ++ publicDns6;
            localZones = sitecLocalZones;
            localRecords = sitecLocalRecords;
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };

          sitecMediaDns = {
            listen = [
              "10.90.20.1"
              "fd42:dead:cafe:20::1"
              "10.90.50.1"
              "fd42:dead:cafe:50::1"
            ];
            allowFrom = [
              "10.90.20.0/24"
              "fd42:dead:cafe:20::/64"
              "10.90.50.0/29"
              "fd42:dead:cafe:50::/64"
            ];
            forwarders = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
            localZones = sitecLocalZones;
            localRecords = sitecLocalRecords;
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };

          sitecPrinterDns = {
            listen = [
              "10.90.30.1"
              "fd42:dead:cafe:30::1"
            ];
            allowFrom = [
              "10.90.30.0/29"
              "fd42:dead:cafe:30::/64"
            ];
            forwarders = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
            localZones = sitecLocalZones;
            localRecords = sitecLocalRecords;
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };

          sitecNasDns = {
            listen = [
              "10.90.40.1"
              "fd42:dead:cafe:40::1"
            ];
            allowFrom = [
              "10.90.40.0/29"
              "fd42:dead:cafe:40::/64"
            ];
            forwarders = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
            localZones = sitecLocalZones;
            localRecords = sitecLocalRecords;
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };

          sitecIotDns = {
            listen = [
              "10.90.60.1"
              "fd42:dead:cafe:60::1"
            ];
            allowFrom = [
              "10.90.60.0/24"
              "fd42:dead:cafe:60::/64"
            ];
            forwarders = [
              "10.90.10.1"
              "fd42:dead:cafe:10::1"
            ];
            advertised = {
              dnsServers = [ "router-self" ];
              rdnss = [ "router-self" ];
            };
          };
        in
        {
          endpoints = {
            sitec-dns-mgmt = {
              ipv4 = [ "10.90.10.1" ];
              ipv6 = [ "fd42:dead:cafe:10::1" ];
            };
          };

          controlPlaneSites = sites:
            sites
            // {
              esp0xdeadbeef =
                sites.esp0xdeadbeef
                // {
                  "site-a" =
                    sites.esp0xdeadbeef."site-a"
                    // {
                      overlays =
                        (sites.esp0xdeadbeef."site-a".overlays or { })
                        // {
                          site-c-storage = {
                            provider = "nebula";
                            ipam = {
                              ipv4.prefix = "100.96.20.0/24";
                              ipv6.prefix = "fd42:dead:beef:ec::/64";
                              nodes = {
                                s-router-core-isp-b = {
                                  addr4 = "100.96.20.1/32";
                                  addr6 = "fd42:dead:beef:ec::1/128";
                                };

                                c-router-core = {
                                  addr4 = "100.96.20.2/32";
                                  addr6 = "fd42:dead:beef:ec::2/128";
                                };

                                nas-node01 = {
                                  addr4 = "100.96.20.10/32";
                                  addr6 = "fd42:dead:beef:ec::10/128";
                                };

                                printer-node01 = {
                                  addr4 = "100.96.20.20/32";
                                  addr6 = "fd42:dead:beef:ec::20/128";
                                };

                                hetzner-nebula-prodtest-01 = {
                                  addr4 = "100.96.20.254/32";
                                  addr6 = "fd42:dead:beef:ec::254/128";
                                };
                              };
                            };
                            nebula = {
                              role = "core-client";
                              lighthouse = {
                                node = "hetzner-nebula-prodtest-01";
                                endpoint = "46.224.173.254";
                                endpoint6 = "2a01:4f8:c013:628b::1";
                                port = 4243;
                              };
                            };
                          };
                        };
                    };

                  "site-c" = {
                    routing = {
                      mode = "bgp";
                      bgp = {
                        asn = 65020;
                        topology = "policy-rr";
                      };
                    };

                    overlays.site-c-storage = {
                      provider = "nebula";
                      ipam = {
                        ipv4.prefix = "100.96.20.0/24";
                        ipv6.prefix = "fd42:dead:beef:ec::/64";
                        nodes = {
                          c-router-core = {
                            addr4 = "100.96.20.2/32";
                            addr6 = "fd42:dead:beef:ec::2/128";
                          };

                          s-router-core-isp-b = {
                            addr4 = "100.96.20.1/32";
                            addr6 = "fd42:dead:beef:ec::1/128";
                          };

                          nas-node01 = {
                            addr4 = "100.96.20.10/32";
                            addr6 = "fd42:dead:beef:ec::10/128";
                          };

                          printer-node01 = {
                            addr4 = "100.96.20.20/32";
                            addr6 = "fd42:dead:beef:ec::20/128";
                          };

                          hetzner-nebula-prodtest-01 = {
                            addr4 = "100.96.20.254/32";
                            addr6 = "fd42:dead:beef:ec::254/128";
                          };
                        };
                      };
                      nebula = {
                        role = "core-client";
                        lighthouse = {
                          node = "hetzner-nebula-prodtest-01";
                          endpoint = "46.224.173.254";
                          endpoint6 = "2a01:4f8:c013:628b::1";
                          port = 4243;
                        };
                      };
                      runtimeNodes = {
                        nas-node01 = {
                          groups = [
                            "lab"
                            "site-c"
                            "storage"
                          ];
                          service = {
                            name = "nebula-runtime";
                            interface = "nebula1";
                          };
                          container = {
                            hostBridge = "nas";
                            profile = "storage-client";
                          };
                        };

                        printer-node01 = {
                          groups = [
                            "lab"
                            "site-c"
                            "printer"
                          ];
                          service = {
                            name = "nebula-runtime";
                            interface = "nebula1";
                          };
                          container = {
                            hostBridge = "printer";
                            profile = "storage-client";
                          };
                        };
                      };
                    };
                  };
                };
            };

          deploymentHost = host:
            host
            // {
              bridgeNetworks =
                host.bridgeNetworks
                // {
                  br-site-c-core-upstream = { };

                  br-site-c-policy-upstream-access-mgmt-wan = { };
                  br-site-c-policy-upstream-access-mgmt-site-c-storage = { };
                  br-site-c-policy-upstream-access-media-wan = { };
                  br-site-c-policy-upstream-access-printer-wan = { };
                  br-site-c-policy-upstream-access-printer-site-c-storage = { };
                  br-site-c-policy-upstream-access-nas-wan = { };
                  br-site-c-policy-upstream-access-nas-site-c-storage = { };
                  br-site-c-policy-upstream-access-iot-wan = { };

                  br-site-c-downstream-policy-access-mgmt = { };
                  br-site-c-downstream-policy-access-media = { };
                  br-site-c-downstream-policy-access-printer = { };
                  br-site-c-downstream-policy-access-nas = { };
                  br-site-c-downstream-policy-access-iot = { };

                  br-site-c-downstream-mgmt = { };
                  br-site-c-downstream-media = { };
                  br-site-c-downstream-printer = { };
                  br-site-c-downstream-nas = { };
                  br-site-c-downstream-iot = { };

                  site-c-mgmt = { };
                  home-users = { };
                  printer = { };
                  nas = { };
                  streaming = { };
                  iot = { };
                };
            };

          realizationNodes = {
            esp0xdeadbeef-site-c-c-router-core = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-core";
              };

              containers.default.runtimeName = "c-router-core";

              ports = {
                upstream-selector = {
                  link = "p2p-c-router-core-c-router-upstream-selector";
                  adapterName = "${"p2p-c-router-core-c-router-upstream-selector"}-upstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-core-upstream";
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

            esp0xdeadbeef-site-c-c-router-access-mgmt = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-access-mgmt";
              };

              containers.default.runtimeName = "c-router-access-mgmt";
              services.dns = policyDerivedDns sitecMgmtDns;

              ports = {
                transit-downstream-selector = {
                  link = "p2p-c-router-access-mgmt-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-mgmt-c-router-downstream-selector"}-transit-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-mgmt";
                  };
                  interface.name = "transit";
                };

                tenant-mgmt = {
                  logicalInterface = "tenant-mgmt";
                  attach = {
                    kind = "bridge";
                    bridge = "site-c-mgmt";
                  };
                  interface = {
                    name = "tenant-mgmt";
                    addr4 = "10.90.10.1/24";
                    addr6 = "fd42:dead:cafe:10::1/64";
                  };
                };
              };

              advertisements = {
                dhcp4.tenant-mgmt = {
                  interface = "tenant-mgmt";
                  id = "mgmt";
                  subnet = "10.90.10.0/24";
                  pool = {
                    start = "10.90.10.100";
                    end = "10.90.10.200";
                  };
                  router = "10.90.10.1";
                  dnsServers = sitecMgmtDns.advertised.dnsServers;
                  domain = "lan.";
                };

                ipv6Ra.tenant-mgmt = {
                  interface = "tenant-mgmt";
                  prefixes = [ "fd42:dead:cafe:10::/64" ];
                  rdnss = sitecMgmtDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-access-media = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-access-media";
              };

              containers.default.runtimeName = "c-router-access-media";
              services.dns = policyDerivedDns sitecMediaDns;
              services.mdns = {
                reflector = true;
                allowInterfaces = [
                  "tenant-home-users"
                  "tenant-streaming"
                ];
                publish = {
                  enable = false;
                  addresses = false;
                };
              };

              ports = {
                transit-downstream-selector = {
                  link = "p2p-c-router-access-media-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-media-c-router-downstream-selector"}-transit-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-media";
                  };
                  interface.name = "transit";
                };

                tenant-home-users = {
                  logicalInterface = "tenant-home-users";
                  attach = {
                    kind = "bridge";
                    bridge = "home-users";
                  };
                  interface = {
                    name = "tenant-home-users";
                    addr4 = "10.90.20.1/24";
                    addr6 = "fd42:dead:cafe:20::1/64";
                  };
                };

                tenant-streaming = {
                  logicalInterface = "tenant-streaming";
                  attach = {
                    kind = "bridge";
                    bridge = "streaming";
                  };
                  interface = {
                    name = "tenant-streaming";
                    addr4 = "10.90.50.1/29";
                    addr6 = "fd42:dead:cafe:50::1/64";
                  };
                };
              };

              advertisements = {
                dhcp4.tenant-home-users = {
                  interface = "tenant-home-users";
                  id = "home-users";
                  subnet = "10.90.20.0/24";
                  pool = {
                    start = "10.90.20.100";
                    end = "10.90.20.200";
                  };
                  router = "10.90.20.1";
                  dnsServers = sitecMediaDns.advertised.dnsServers;
                  domain = "lan.";
                };

                dhcp4.tenant-streaming = {
                  interface = "tenant-streaming";
                  id = "streaming";
                  subnet = "10.90.50.0/29";
                  pool = {
                    start = "10.90.50.3";
                    end = "10.90.50.6";
                  };
                  router = "10.90.50.1";
                  dnsServers = sitecMediaDns.advertised.dnsServers;
                  domain = "lan.";
                };

                ipv6Ra.tenant-home-users = {
                  interface = "tenant-home-users";
                  prefixes = [ "fd42:dead:cafe:20::/64" ];
                  rdnss = sitecMediaDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };

                ipv6Ra.tenant-streaming = {
                  interface = "tenant-streaming";
                  prefixes = [ "fd42:dead:cafe:50::/64" ];
                  rdnss = sitecMediaDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-access-printer = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-access-printer";
              };

              containers.default.runtimeName = "c-router-access-printer";
              services.dns = policyDerivedDns sitecPrinterDns;

              ports = {
                transit-downstream-selector = {
                  link = "p2p-c-router-access-printer-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-printer-c-router-downstream-selector"}-transit-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-printer";
                  };
                  interface.name = "transit";
                };

                tenant-printer = {
                  logicalInterface = "tenant-printer";
                  attach = {
                    kind = "bridge";
                    bridge = "printer";
                  };
                  interface = {
                    name = "tenant-printer";
                    addr4 = "10.90.30.1/29";
                    addr6 = "fd42:dead:cafe:30::1/64";
                  };
                };
              };

              advertisements = {
                dhcp4.tenant-printer = {
                  interface = "tenant-printer";
                  id = "printer";
                  subnet = "10.90.30.0/29";
                  pool = {
                    start = "10.90.30.3";
                    end = "10.90.30.6";
                  };
                  router = "10.90.30.1";
                  dnsServers = sitecPrinterDns.advertised.dnsServers;
                  domain = "lan.";
                };

                ipv6Ra.tenant-printer = {
                  interface = "tenant-printer";
                  prefixes = [ "fd42:dead:cafe:30::/64" ];
                  rdnss = sitecPrinterDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-access-nas = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-access-nas";
              };

              containers.default.runtimeName = "c-router-access-nas";
              services.dns = policyDerivedDns sitecNasDns;

              ports = {
                transit-downstream-selector = {
                  link = "p2p-c-router-access-nas-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-nas-c-router-downstream-selector"}-transit-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-nas";
                  };
                  interface.name = "transit";
                };

                tenant-nas = {
                  logicalInterface = "tenant-nas";
                  attach = {
                    kind = "bridge";
                    bridge = "nas";
                  };
                  interface = {
                    name = "tenant-nas";
                    addr4 = "10.90.40.1/29";
                    addr6 = "fd42:dead:cafe:40::1/64";
                  };
                };
              };

              advertisements = {
                dhcp4.tenant-nas = {
                  interface = "tenant-nas";
                  id = "nas";
                  subnet = "10.90.40.0/29";
                  pool = {
                    start = "10.90.40.3";
                    end = "10.90.40.6";
                  };
                  router = "10.90.40.1";
                  dnsServers = sitecNasDns.advertised.dnsServers;
                  domain = "lan.";
                };

                ipv6Ra.tenant-nas = {
                  interface = "tenant-nas";
                  prefixes = [ "fd42:dead:cafe:40::/64" ];
                  rdnss = sitecNasDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-access-iot = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-access-iot";
              };

              containers.default.runtimeName = "c-router-access-iot";
              services.dns = policyDerivedDns sitecIotDns;

              ports = {
                transit-downstream-selector = {
                  link = "p2p-c-router-access-iot-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-iot-c-router-downstream-selector"}-transit-downstream-selector";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-iot";
                  };
                  interface.name = "transit";
                };

                tenant-iot = {
                  logicalInterface = "tenant-iot";
                  attach = {
                    kind = "bridge";
                    bridge = "iot";
                  };
                  interface = {
                    name = "tenant-iot";
                    addr4 = "10.90.60.1/24";
                    addr6 = "fd42:dead:cafe:60::1/64";
                  };
                };
              };

              advertisements = {
                dhcp4.tenant-iot = {
                  interface = "tenant-iot";
                  id = "iot";
                  subnet = "10.90.60.0/24";
                  pool = {
                    start = "10.90.60.100";
                    end = "10.90.60.200";
                  };
                  router = "10.90.60.1";
                  dnsServers = sitecIotDns.advertised.dnsServers;
                  domain = "lan.";
                };

                ipv6Ra.tenant-iot = {
                  interface = "tenant-iot";
                  prefixes = [ "fd42:dead:cafe:60::/64" ];
                  rdnss = sitecIotDns.advertised.rdnss;
                  dnssl = [ "lan." ];
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-downstream-selector = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-downstream-selector";
              };

              containers.default.runtimeName = "c-router-downstream-selector";

              ports = {
                policy-mgmt = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-mgmt";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-mgmt"}-policy-mgmt";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-mgmt";
                  };
                  interface.name = "policy-mgmt";
                };

                access-mgmt = {
                  link = "p2p-c-router-access-mgmt-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-mgmt-c-router-downstream-selector"}-access-mgmt";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-mgmt";
                  };
                  interface.name = "access-mgmt";
                };

                policy-media = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-media";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-media"}-policy-media";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-media";
                  };
                  interface.name = "policy-media";
                };

                access-media = {
                  link = "p2p-c-router-access-media-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-media-c-router-downstream-selector"}-access-media";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-media";
                  };
                  interface.name = "access-media";
                };

                policy-printer = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-printer";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-printer"}-policy-printer";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-printer";
                  };
                  interface.name = "policy-printer";
                };

                access-printer = {
                  link = "p2p-c-router-access-printer-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-printer-c-router-downstream-selector"}-access-printer";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-printer";
                  };
                  interface.name = "access-printer";
                };

                policy-nas = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-nas";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-nas"}-policy-nas";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-nas";
                  };
                  interface.name = "policy-nas";
                };

                access-nas = {
                  link = "p2p-c-router-access-nas-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-nas-c-router-downstream-selector"}-access-nas";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-nas";
                  };
                  interface.name = "access-nas";
                };

                policy-iot = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-iot";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-iot"}-policy-iot";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-iot";
                  };
                  interface.name = "policy-iot";
                };

                access-iot = {
                  link = "p2p-c-router-access-iot-c-router-downstream-selector";
                  adapterName = "${"p2p-c-router-access-iot-c-router-downstream-selector"}-access-iot";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-iot";
                  };
                  interface.name = "access-iot";
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-policy = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-policy";
              };

              containers.default.runtimeName = "c-router-policy";

              ports = {
                upstream-mgmt-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-wan"}-upstream-mgmt-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-mgmt-wan";
                  };
                  interface.name = "up-mgmt-wan";
                };

                upstream-mgmt-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-site-c-storage"}-upstream-mgmt-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-mgmt-site-c-storage";
                  };
                  interface.name = "up-mgt-sto";
                };

                upstream-media-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-media--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-media--uplink-wan"}-upstream-media-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-media-wan";
                  };
                  interface.name = "up-med-wan";
                };

                upstream-printer-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-site-c-storage"}-upstream-printer-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-printer-site-c-storage";
                  };
                  interface.name = "up-prn-sto";
                };

                upstream-printer-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-wan"}-upstream-printer-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-printer-wan";
                  };
                  interface.name = "up-prn-wan";
                };

                upstream-nas-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-site-c-storage"}-upstream-nas-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-nas-site-c-storage";
                  };
                  interface.name = "up-nas-storage";
                };

                upstream-nas-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-wan"}-upstream-nas-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-nas-wan";
                  };
                  interface.name = "up-nas-wan";
                };

                upstream-iot-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-iot--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-iot--uplink-wan"}-upstream-iot-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-iot-wan";
                  };
                  interface.name = "up-iot-wan";
                };

                downstream-mgmt = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-mgmt";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-mgmt"}-downstream-mgmt";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-mgmt";
                  };
                  interface.name = "downstream-mgmt";
                };

                downstream-media = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-media";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-media"}-downstream-media";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-media";
                  };
                  interface.name = "down-media";
                };

                downstream-printer = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-printer";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-printer"}-downstream-printer";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-printer";
                  };
                  interface.name = "down-printer";
                };

                downstream-nas = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-nas";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-nas"}-downstream-nas";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-nas";
                  };
                  interface.name = "downstream-nas";
                };

                downstream-iot = {
                  link = "p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-iot";
                  adapterName = "${"p2p-c-router-downstream-selector-c-router-policy--access-c-router-access-iot"}-downstream-iot";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-downstream-policy-access-iot";
                  };
                  interface.name = "downstream-iot";
                };
              };
            };

            esp0xdeadbeef-site-c-c-router-upstream-selector = {
              host = "s-router-test";
              platform = "nixos-container";

              logicalNode = {
                enterprise = "esp0xdeadbeef";
                site = "site-c";
                name = "c-router-upstream-selector";
              };

              containers.default.runtimeName = "c-router-upstream-selector";

              ports = {
                core = {
                  link = "p2p-c-router-core-c-router-upstream-selector";
                  adapterName = "${"p2p-c-router-core-c-router-upstream-selector"}-core";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-core-upstream";
                  };
                  interface.name = "core";
                };

                policy-mgmt-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-wan"}-policy-mgmt-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-mgmt-wan";
                  };
                  interface.name = "policy-mgmt-wan";
                };

                policy-mgmt-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-mgmt--uplink-site-c-storage"}-policy-mgmt-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-mgmt-site-c-storage";
                  };
                  interface.name = "pol-mgt-sto";
                };

                policy-media-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-media--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-media--uplink-wan"}-policy-media-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-media-wan";
                  };
                  interface.name = "pol-med-wan";
                };

                policy-printer-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-site-c-storage"}-policy-printer-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-printer-site-c-storage";
                  };
                  interface.name = "pol-prn-sto";
                };

                policy-printer-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-printer--uplink-wan"}-policy-printer-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-printer-wan";
                  };
                  interface.name = "pol-prn-wan";
                };

                policy-nas-site-c-storage = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-site-c-storage";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-site-c-storage"}-policy-nas-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-nas-site-c-storage";
                  };
                  interface.name = "pol-nas-sto";
                };

                policy-nas-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-nas--uplink-wan"}-policy-nas-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-nas-wan";
                  };
                  interface.name = "pol-nas-wan";
                };

                policy-iot-wan = {
                  link = "p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-iot--uplink-wan";
                  adapterName = "${"p2p-c-router-policy-c-router-upstream-selector--access-c-router-access-iot--uplink-wan"}-policy-iot-wan";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-c-policy-upstream-access-iot-wan";
                  };
                  interface.name = "policy-iot-wan";
                };
              };
            };
          };
        };
    in
    siteCBuilder {
      inherit base publicDns4 publicDns6 policyDerivedDns;
    };
in
base
// {
  endpoints =
    (base.endpoints or { })
    // {
      site-dns-mgmt = {
        ipv4 = [ "10.20.10.1" ];
        ipv6 = [ "fd42:dead:beef:10::1" ];
      };

      nebula01 = {
        ipv4 = [ "10.20.30.10" ];
        ipv6 = [ "fd42:dead:beef:30::10" ];
      };
    }
    // siteC.endpoints;

  controlPlane =
    base.controlPlane
    // {
      sites =
        siteC.controlPlaneSites (
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
                      nodes = {
                        s-router-core-isp-b = {
                          addr4 = "100.96.10.1/32";
                          addr6 = "fd42:dead:beef:ee::1/128";
                        };

                        nebula-core = {
                          addr4 = "100.96.10.10/32";
                          addr6 = "fd42:dead:beef:ee::10/128";
                        };

                        hetzner-nebula-prodtest-01 = {
                          addr4 = "100.96.10.254/32";
                          addr6 = "fd42:dead:beef:ee::254/128";
                        };
                      };
                    };
                    nebula = {
                      role = "core-client";
                      lighthouse = {
                        node = "hetzner-nebula-prodtest-01";
                        endpoint = "46.224.173.254";
                        endpoint6 = "2a01:4f8:c013:628b::1";
                        port = 4242;
                      };
                    };
                    runtimeNodes = {
                      nebula-core = {
                        groups = [
                          "lab"
                          "core"
                        ];
                        service = {
                          name = "nebula-runtime";
                          interface = "nebula1";
                        };
                        container = {
                          hostBridge = "br-uplink1";
                          profile = "core-client";
                        };
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
                  nodes = {
                    b-router-core = {
                      addr4 = "100.96.10.2/32";
                      addr6 = "fd42:dead:beef:ee::2/128";
                    };

                    branch-node01 = {
                      addr4 = "100.96.10.20/32";
                      addr6 = "fd42:dead:beef:ee::20/128";
                    };

                    hostile-node01 = {
                      addr4 = "100.96.10.30/32";
                      addr6 = "fd42:dead:beef:ee::30/128";
                    };

                    hetzner-nebula-prodtest-01 = {
                      addr4 = "100.96.10.254/32";
                      addr6 = "fd42:dead:beef:ee::254/128";
                    };
                  };
                };
                nebula = {
                  role = "core-client";
                  lighthouse = {
                    node = "hetzner-nebula-prodtest-01";
                    endpoint = "46.224.173.254";
                    endpoint6 = "2a01:4f8:c013:628b::1";
                    port = 4242;
                  };
                };
                runtimeNodes = {
                  branch-node01 = {
                    groups = [
                      "lab"
                      "branch"
                    ];
                    service = {
                      name = "nebula-runtime";
                      interface = "nebula1";
                    };
                    container = {
                      hostBridge = "branch";
                      profile = "branch-web";
                    };
                  };

                  hostile-node01 = {
                    groups = [
                      "lab"
                      "hostile"
                    ];
                    unsafeRoutes = [
                      { route = "0.0.0.0/1"; }
                      { route = "128.0.0.0/1"; }
                      { route = "::/1"; }
                      { route = "8000::/1"; }
                    ];
                    service = {
                      name = "nebula-runtime";
                      interface = "nebula1";
                    };
                    container = {
                      hostBridge = "hostile";
                      profile = "hostile-exit";
                    };
                  };
                };
              };
            };
          };
        }
        );
    };

  deployment =
    base.deployment
    // {
      hosts =
        base.deployment.hosts
        // {
          s-router-test =
            siteC.deploymentHost (
              host
              // {
              # Ensure WAN-only nodes in this profile resolve to the ISP-B uplink
              # instead of falling back to an unrelated host uplink.
              wanUplink = "uplink-isp-b";

              bridgeNetworks =
                host.bridgeNetworks
                // {
                  br-site-a-policy-upstream-access-admin-east-west = { };
                  br-site-a-policy-upstream-access-client-east-west = { };
                  br-site-a-policy-upstream-access-client2-east-west = { };
                  br-site-a-policy-upstream-access-mgmt-east-west = { };
                  br-site-a-policy-upstream-access-mgmt-site-c-storage = { };
                  br-site-a-policy-upstream-access-client2-isp-a = { };
                  br-site-a-policy-upstream-access-client2-isp-b = { };
                  br-site-a-downstream-policy-access-client2 = { };
                  br-site-a-downstream-client2 = { };
                  client2 = { };
                  br-site-a-downstream-policy-access-dmz = { };
                  br-site-a-downstream-dmz = { };
                  dmz = { };

                  br-site-b-core-upstream = { };
                  br-site-b-policy-upstream-access-branch-east-west = { };
                  br-site-b-policy-upstream-access-branch = { };
                  br-site-b-policy-upstream-access-hostile = { };
                  br-site-b-downstream-policy-access-branch = { };
                  br-site-b-downstream-policy-access-hostile = { };
                  br-site-b-downstream-branch = { };
                  br-site-b-downstream-hostile = { };
                  branch = { };
                  hostile = { };
                };
              }
            );
        };
    };

  realization = {
    nodes =
      siteANodes
      // {
        esp0xdeadbeef-site-a-s-router-access-admin =
          siteANodes.esp0xdeadbeef-site-a-s-router-access-admin
          // {
            services.dns = policyDerivedDns siteANodes.esp0xdeadbeef-site-a-s-router-access-admin.services.dns;
            advertisements =
              overrideAdvertisedRouterSelf
                siteANodes.esp0xdeadbeef-site-a-s-router-access-admin.advertisements
                "tenant-admin";
          };

        esp0xdeadbeef-site-a-s-router-access-client =
          siteANodes.esp0xdeadbeef-site-a-s-router-access-client
          // {
            services.dns = policyDerivedDns siteANodes.esp0xdeadbeef-site-a-s-router-access-client.services.dns;
            advertisements =
              overrideAdvertisedRouterSelf
                siteANodes.esp0xdeadbeef-site-a-s-router-access-client.advertisements
                "tenant-client";
          };

        esp0xdeadbeef-site-a-s-router-access-mgmt =
          siteANodes.esp0xdeadbeef-site-a-s-router-access-mgmt
          // {
            services.dns = policyDerivedDns siteANodes.esp0xdeadbeef-site-a-s-router-access-mgmt.services.dns;
            advertisements =
              overrideAdvertisedRouterSelf
                siteANodes.esp0xdeadbeef-site-a-s-router-access-mgmt.advertisements
                "tenant-mgmt";
          };

        esp0xdeadbeef-site-a-s-router-access-dmz = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "esp0xdeadbeef";
            site = "site-a";
            name = "s-router-access-dmz";
          };

          containers.default.runtimeName = "s-router-access-dmz";
          services.dns = policyDerivedDns dmzDns;

          ports = {
            transit-downstream-selector = {
              link = "p2p-s-router-access-dmz-s-router-downstream-selector";
              adapterName = "${"p2p-s-router-access-dmz-s-router-downstream-selector"}-transit-downstream-selector";
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

        esp0xdeadbeef-site-a-s-router-access-client2 = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "esp0xdeadbeef";
            site = "site-a";
            name = "s-router-access-client2";
          };

          containers.default.runtimeName = "s-router-access-client2";
          services.dns = policyDerivedDns {
            listen = [
              "10.20.40.1"
              "fd42:dead:beef:40::1"
            ];
            allowFrom = [
              "10.20.40.0/24"
              "fd42:dead:beef:40::/64"
            ];
            forwarders = publicDns4 ++ publicDns6;
          };

          ports = {
            transit-downstream-selector = {
              link = "p2p-s-router-access-client2-s-router-downstream-selector";
              adapterName = "${"p2p-s-router-access-client2-s-router-downstream-selector"}-transit-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-a-downstream-client2";
              };
              interface.name = "transit";
            };

            tenant-client2 = {
              logicalInterface = "tenant-client2";
              attach = {
                kind = "bridge";
                bridge = "client2";
              };
              interface = {
                name = "tenant-client2";
                addr4 = "10.20.40.1/24";
                addr6 = "fd42:dead:beef:40::1/64";
              };
            };
          };

          advertisements = {
            dhcp4.tenant-client2 = {
              interface = "tenant-client2";
              id = "client2";
              subnet = "10.20.40.0/24";
              pool = {
                start = "10.20.40.100";
                end = "10.20.40.200";
              };
              router = "10.20.40.1";
              dnsServers = [ "router-self" ];
              domain = "lan.";
            };

            ipv6Ra.tenant-client2 = {
              interface = "tenant-client2";
              prefixes = [ "fd42:dead:beef:40::/64" ];
              rdnss = [ "router-self" ];
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
                  adapterName = "${"p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz"}-policy-dmz";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-dmz";
                  };
                  interface.name = "policy-dmz";
                };

                access-dmz = {
                  link = "p2p-s-router-access-dmz-s-router-downstream-selector";
                  adapterName = "${"p2p-s-router-access-dmz-s-router-downstream-selector"}-access-dmz";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-dmz";
                  };
                  interface.name = "access-dmz";
                };

                policy-client2 = {
                  link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2";
                  adapterName = "${"p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2"}-policy-client2";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-client2";
                  };
                  interface.name = "policy-client2";
                };

                access-client2 = {
                  link = "p2p-s-router-access-client2-s-router-downstream-selector";
                  adapterName = "${"p2p-s-router-access-client2-s-router-downstream-selector"}-access-client2";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-client2";
                  };
                  interface.name = "access-client2";
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
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west"}-upstream-admin-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-admin-east-west";
                  };
                  interface.name = "up-adm-ew";
                };

                upstream-client-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west"}-upstream-client-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client-east-west";
                  };
                  interface.name = "up-cli-ew";
                };

                upstream-client2-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west"}-upstream-client2-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-east-west";
                  };
                  interface.name = "up-cl2-ew";
                };

                upstream-client2-isp-a = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a"}-upstream-client2-isp-a";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-isp-a";
                  };
                  interface.name = "up-cl2-a";
                };

                upstream-client2-isp-b = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b"}-upstream-client2-isp-b";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-isp-b";
                  };
                  interface.name = "up-cl2-b";
                };


                upstream-mgmt-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west"}-upstream-mgmt-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
                  };
                  interface.name = "up-mgt-ew";
                };

                upstream-mgmt-site-c-storage = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-site-c-storage";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-site-c-storage"}-upstream-mgmt-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-site-c-storage";
                  };
                  interface.name = "up-mgt-sitec";
                };

                downstream-dmz = {
                  link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz";
                  adapterName = "${"p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-dmz"}-downstream-dmz";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-dmz";
                  };
                  interface.name = "downstream-dmz";
                };

                downstream-client2 = {
                  link = "p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2";
                  adapterName = "${"p2p-s-router-downstream-selector-s-router-policy-only--access-s-router-access-client2"}-downstream-client2";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-downstream-policy-access-client2";
                  };
                  interface.name = "downstream-client2";
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
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-admin--uplink-east-west"}-policy-admin-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-admin-east-west";
                  };
                  interface.name = "pol-adm-ew";
                };

                policy-client-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client--uplink-east-west"}-policy-client-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client-east-west";
                  };
                  interface.name = "pol-cli-ew";
                };

                policy-client2-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-east-west"}-policy-client2-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-east-west";
                  };
                  interface.name = "pol-cl2-ew";
                };

                policy-client2-isp-a = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-a"}-policy-client2-isp-a";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-isp-a";
                  };
                  interface.name = "pol-cl2-a";
                };

                policy-client2-isp-b = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-client2--uplink-isp-b"}-policy-client2-isp-b";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-client2-isp-b";
                  };
                  interface.name = "pol-cl2-b";
                };

                policy-mgmt-east-west = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-east-west"}-policy-mgmt-east-west";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-east-west";
                  };
                  interface.name = "pol-mgt-ew";
                };

                policy-mgmt-site-c-storage = {
                  link = "p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-site-c-storage";
                  adapterName = "${"p2p-s-router-policy-only-s-router-upstream-selector--access-s-router-access-mgmt--uplink-site-c-storage"}-policy-mgmt-site-c-storage";
                  attach = {
                    kind = "bridge";
                    bridge = "br-site-a-policy-upstream-access-mgmt-site-c-storage";
                  };
                  interface.name = "pol-mgt-sitec";
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

          ports = {
            upstream-selector = {
              link = "p2p-b-router-core-b-router-upstream-selector";
              adapterName = "${"p2p-b-router-core-b-router-upstream-selector"}-upstream-selector";
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
          services.dns = branchAccessDns;

          ports = {
            transit-downstream-selector = {
              link = "p2p-b-router-access-branch-b-router-downstream-selector";
              adapterName = "${"p2p-b-router-access-branch-b-router-downstream-selector"}-transit-downstream-selector";
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
              dnsServers = branchAccessDns.advertised.dnsServers;
              domain = "lan.";
            };

            ipv6Ra.tenant-branch = {
              interface = "tenant-branch";
              prefixes = [ "fd42:dead:feed:10::/64" ];
              rdnss = branchAccessDns.advertised.rdnss;
              dnssl = [ "lan." ];
            };
          };
        };

        espbranch-site-b-b-router-access-hostile = {
          host = "s-router-test";
          platform = "nixos-container";

          logicalNode = {
            enterprise = "espbranch";
            site = "site-b";
            name = "b-router-access-hostile";
          };

          containers.default.runtimeName = "b-router-access-hostile";
          services.dns = hostileAccessDns;

          ports = {
            transit-downstream-selector = {
              link = "p2p-b-router-access-hostile-b-router-downstream-selector";
              adapterName = "${"p2p-b-router-access-hostile-b-router-downstream-selector"}-transit-downstream-selector";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-hostile";
              };
              interface.name = "transit";
            };

            tenant-hostile = {
              logicalInterface = "tenant-hostile";
              attach = {
                kind = "bridge";
                bridge = "hostile";
              };
              interface = {
                name = "tenant-hostile";
                addr4 = "10.70.10.1/24";
                addr6 = "fd42:dead:feed:70::1/64";
              };
            };
          };

          advertisements = {
            dhcp4.tenant-hostile = {
              interface = "tenant-hostile";
              id = "hostile";
              subnet = "10.70.10.0/24";
              pool = {
                start = "10.70.10.100";
                end = "10.70.10.200";
              };
              router = "10.70.10.1";
              dnsServers = hostileAccessDns.advertised.dnsServers;
              domain = "lan.";
            };

            ipv6Ra.tenant-hostile = {
              interface = "tenant-hostile";
              prefixes = [ "fd42:dead:feed:70::/64" ];
              rdnss = hostileAccessDns.advertised.rdnss;
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
              adapterName = "${"p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch"}-policy-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-branch";
              };
              interface.name = "policy-branch";
            };

            access-branch = {
              link = "p2p-b-router-access-branch-b-router-downstream-selector";
              adapterName = "${"p2p-b-router-access-branch-b-router-downstream-selector"}-access-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-branch";
              };
              interface.name = "access-branch";
            };

            policy-hostile = {
              link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile";
              adapterName = "${"p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile"}-policy-hostile";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-hostile";
              };
              interface.name = "policy-hostile";
            };

            access-hostile = {
              link = "p2p-b-router-access-hostile-b-router-downstream-selector";
              adapterName = "${"p2p-b-router-access-hostile-b-router-downstream-selector"}-access-hostile";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-hostile";
              };
              interface.name = "access-hostile";
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
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west"}-upstream-branch-east-west";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch-east-west";
              };
              interface.name = "up-branch-ew";
            };

            upstream-branch = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan"}-upstream-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch";
              };
              interface.name = "upstream-branch";
            };

            downstream-branch = {
              link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch";
              adapterName = "${"p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-branch"}-downstream-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-branch";
              };
              interface.name = "downstream-branch";
            };

            upstream-hostile = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan";
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan"}-upstream-hostile";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-hostile";
              };
              interface.name = "up-hostile";
            };

            downstream-hostile = {
              link = "p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile";
              adapterName = "${"p2p-b-router-downstream-selector-b-router-policy--access-b-router-access-hostile"}-downstream-hostile";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-downstream-policy-access-hostile";
              };
              interface.name = "downstream-hostile";
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
              adapterName = "${"p2p-b-router-core-b-router-upstream-selector"}-core";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-core-upstream";
              };
              interface.name = "core";
            };

            policy-branch-east-west = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west";
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-east-west"}-policy-branch-east-west";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch-east-west";
              };
              interface.name = "pol-branch-ew";
            };

            policy-branch = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan";
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-branch--uplink-wan"}-policy-branch";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-branch";
              };
              interface.name = "policy-branch";
            };

            policy-hostile = {
              link = "p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan";
              adapterName = "${"p2p-b-router-policy-b-router-upstream-selector--access-b-router-access-hostile--uplink-wan"}-policy-hostile";
              attach = {
                kind = "bridge";
                bridge = "br-site-b-policy-upstream-access-hostile";
              };
              interface.name = "policy-hostile";
            };
          };
        };
        }
      // siteC.realizationNodes;
  };
}
