{
  lib,
  debugPackages,
}:

let
  evalExtraModules =
    moduleArgs: modules:
    map (module: if builtins.isFunction module then module moduleArgs else module) modules;
in
{
  mkDmzEndpoint =
    {
      addr4,
      gw4,
      addr6,
      gw6,
      dnsServers ? [
        gw4
        gw6
      ],
      allowedTcpPorts ? [ ],
      allowedUdpPorts ? [ ],
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
          networking.firewall.enable = true;
          networking.firewall.allowedTCPPorts = allowedTcpPorts;
          networking.firewall.allowedUDPPorts = allowedUdpPorts;

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

          environment.systemPackages = debugPackages.common;
        }
      ]
      ++ evalExtraModules moduleArgs extraModules
    );
}
