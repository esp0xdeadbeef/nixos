{
  lib,
  nebulaRuntime,
  runtimeFacts,
}:
let
  inherit (nebulaRuntime) hostNetworks internalWan renderedNetdevs;
  inherit (runtimeFacts) publicIPv4Gateway primaryInterfaceMac;
in
{
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
  };

  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.netdevs = renderedNetdevs;
  systemd.network.networks =
    lib.recursiveUpdate
      (
        hostNetworks
        // {
          "20-hetzner-public" = {
            matchConfig.MACAddress = primaryInterfaceMac;
            linkConfig = {
              ActivationPolicy = "always-up";
              RequiredForOnline = "routable";
            };
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = false;
            };
            routes = [
              {
                Destination = "${publicIPv4Gateway}/32";
                Scope = "link";
              }
              { Gateway = publicIPv4Gateway; }
              { Gateway = "fe80::1"; }
            ];
          };
        }
      )
      {
        "30-br-wan" = {
          matchConfig.Name = "br-wan";
          linkConfig = {
            ActivationPolicy = "always-up";
            RequiredForOnline = "no";
          };
          networkConfig = {
            DHCP = "no";
            DHCPServer = true;
            ConfigureWithoutCarrier = true;
            IPv4Forwarding = true;
            IPv6Forwarding = true;
            IPv6AcceptRA = false;
          };
          address = [
            internalWan.hostAddress4
            internalWan.hostAddress6
          ];
          dhcpServerConfig = {
            PoolOffset = 10;
            PoolSize = 32;
            EmitDNS = false;
          };
        };
      };
}
