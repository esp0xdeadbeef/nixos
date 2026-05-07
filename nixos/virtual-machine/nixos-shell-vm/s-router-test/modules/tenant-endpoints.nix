{
  lib,
  debugPackages,
}:

let
  evalExtraModules =
    moduleArgs: modules:
    map (module: if builtins.isFunction module then module moduleArgs else module) modules;

  mkTenantEndpoint =
    _bridge:
    { ... }:
    {
      system.stateVersion = "25.11";
      networking.useNetworkd = true;
      systemd.network.enable = true;
      networking.useDHCP = false;
      networking.useHostResolvConf = false;
      services.resolved.enable = true;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = true;
        };
      };

      environment.systemPackages = debugPackages.common;
    };

  mkStaticTenantEndpoint =
    {
      addr4,
      gw4,
      addr6,
      gw6,
      mdnsClient ? false,
      dnsServers ? [
        gw4
        gw6
      ],
      hostname ? null,
      extraModules ? [ ],
    }:
    { lib, ... }@moduleArgs:
    lib.mkMerge (
      [
        {
          system.stateVersion = "25.11";
          networking.useNetworkd = true;
          systemd.network.enable = true;
          networking.useDHCP = false;
          networking.useHostResolvConf = false;
          services.resolved.enable = true;

          systemd.network.networks."10-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig = {
              Address = [
                addr4
                addr6
              ];
              DNS = dnsServers;
              Domains = [ "lan." ];
              IPv6AcceptRA = false;
              MulticastDNS = "yes";
            };
            routes = [
              {
                Destination = "0.0.0.0/0";
                Gateway = gw4;
              }
              {
                Destination = "::/0";
                Gateway = gw6;
              }
            ];
          };

          environment.systemPackages = debugPackages.endpoint;

          services.avahi = lib.mkIf mdnsClient {
            enable = true;
            nssmdns4 = true;
            nssmdns6 = true;
            publish = {
              enable = false;
              addresses = false;
              workstation = false;
            };
          };
        }
      ]
      ++ lib.optional (hostname != null) { networking.hostName = hostname; }
      ++ evalExtraModules moduleArgs extraModules
    );
in
{
  inherit mkStaticTenantEndpoint mkTenantEndpoint;
}
