{
  base,
  publicDns4,
  publicDns6,
  policyDerivedDns,
}:
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
    }
