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
      enableTun = true;
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
      enableTun = true;
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
          networking.firewall.allowedUDPPorts = [ 4242 ];
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

    hostile-node01 = {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      hostBridge = "hostile";
      bindMounts = mkNebulaProfileMount "hostile-node01";

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

          systemd.network.networks."20-nebula1" = {
            matchConfig.Name = "nebula1";
            networkConfig = {
              IPv6AcceptRA = false;
              ConfigureWithoutCarrier = true;
            };
            routingPolicyRules = [
              {
                Priority = 100;
                To = "46.224.173.254/32";
                Table = 254;
                Family = "ipv4";
              }
              {
                Priority = 101;
                To = "2a01:4f8:c013:628b::1/128";
                Table = 254;
                Family = "ipv6";
              }
              {
                Priority = 110;
                Table = 100;
                Family = "ipv4";
              }
              {
                Priority = 111;
                Table = 100;
                Family = "ipv6";
              }
            ];
            routes = [
              {
                Destination = "0.0.0.0/1";
                Gateway = "100.96.10.254";
                Table = 100;
              }
              {
                Destination = "128.0.0.0/1";
                Gateway = "100.96.10.254";
                Table = 100;
              }
              {
                Destination = "::/1";
                Gateway = "fd42:dead:beef:ee::254";
                Table = 100;
              }
              {
                Destination = "8000::/1";
                Gateway = "fd42:dead:beef:ee::254";
                Table = 100;
              }
            ];
          };
        };
        firewallModule = {
          services.resolved.enable = true;
          services.resolved.extraConfig = ''
            FallbackDNS=
          '';

          networking.firewall.enable = false;
          networking.nftables.enable = true;
          networking.nftables.ruleset = ''
            table inet hostile {
              chain input {
                type filter hook input priority filter; policy drop;
                iifname "lo" accept
                ct state established,related accept
                iifname "eth0" udp sport 67 udp dport 68 accept
                iifname "eth0" ip protocol icmp accept
                iifname "eth0" ip6 nexthdr icmpv6 accept
                iifname "nebula1" accept
              }

              chain forward {
                type filter hook forward priority filter; policy drop;
              }

              chain output {
                type filter hook output priority filter; policy drop;
                oifname "lo" accept
                ct state established,related accept

                oifname "eth0" ip daddr 255.255.255.255 udp dport 67 accept
                oifname "eth0" ip6 nexthdr icmpv6 accept
                oifname "eth0" ip protocol icmp accept
                oifname "eth0" ip daddr 46.224.173.254 udp dport 4242 accept
                oifname "eth0" ip6 daddr 2a01:4f8:c013:628b::1 udp dport 4242 accept

                oifname "eth0" ip daddr 10.70.10.1 udp dport 53 accept
                oifname "eth0" ip daddr 10.70.10.1 tcp dport 53 accept
                oifname "eth0" ip6 daddr fd42:dead:feed:70::1 udp dport 53 accept
                oifname "eth0" ip6 daddr fd42:dead:feed:70::1 tcp dport 53 accept

                udp dport 53 drop
                tcp dport 53 drop

                oifname "nebula1" accept
              }
            }
          '';
        };
      };
    };
  }
else
  { }
