{
  renderedHostNetwork,
  mkNebulaNode,
  mkNebulaProfileMount,
}:
if renderedHostNetwork.bridges ? branch then
  {
    nebula-core = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "br-uplink1";
      bindMounts = mkNebulaProfileMount "nebula-core";

      config = mkNebulaNode {
        networkModule = {
          systemd.network.networks."10-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = true;
            };
            linkConfig.RequiredForOnline = "no";
          };
        };
        firewallModule = {
          networking.firewall.enable = true;
          networking.firewall.allowedTCPPorts = [ 4242 ];
          networking.firewall.allowedUDPPorts = [ 4242 ];
        };
      };
    };

    branch-node01 = {
      autoStart = true;
      privateNetwork = true;
      hostBridge = "branch";
      bindMounts = mkNebulaProfileMount "branch-node01";

      config = mkNebulaNode {
        networkModule = {
          systemd.network.networks."10-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = true;
            };
            linkConfig.RequiredForOnline = "no";
          };
        };
        firewallModule = {
          networking.firewall.enable = true;
          networking.firewall.interfaces.nebula1.allowedTCPPorts = [ 8081 ];
        };
        extraModules = [
          ({ pkgs, ... }: {
            systemd.services.branch-overlay-web = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.python3}/bin/python -m http.server 8081 --bind 0.0.0.0";
                Restart = "always";
              };
            };
          })
        ];
      };
    };
  }
else
  { }
