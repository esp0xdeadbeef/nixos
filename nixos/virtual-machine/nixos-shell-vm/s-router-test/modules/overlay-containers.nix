{
  lib,
  nebulaRuntimePlan,
  mkNebulaNode,
  mkNebulaProfileMount,
}:

let
  mkDhcpNetworkModule = {
    systemd.network.networks."10-eth0" = {
      matchConfig.Name = "eth0";
      networkConfig = {
        DHCP = "ipv4";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  coreClientContainer = {
    networkModule = mkDhcpNetworkModule;
    firewallModule = {
      networking.firewall.enable = true;
      networking.firewall.allowedTCPPorts = [ 4242 ];
      networking.firewall.allowedUDPPorts = [ 4242 ];
    };
  };

  branchWebContainer = {
    networkModule = mkDhcpNetworkModule;
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

  hostileExitContainer = {
    networkModule = {
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP = "ipv4";
          DNS = [
            "10.70.10.1"
            "fd42:dead:feed:70::1"
          ];
          Domains = [ "lan." ];
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
            Priority = 80;
            To = "10.70.10.0/24";
            Table = 254;
            Family = "ipv4";
          }
          {
            Priority = 81;
            To = "fd42:dead:feed:70::/64";
            Table = 254;
            Family = "ipv6";
          }
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
            Priority = 105;
            To = "100.96.10.0/24";
            Table = 254;
            Family = "ipv4";
          }
          {
            Priority = 106;
            To = "fd42:dead:beef:ee::/64";
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
      networking.resolvconf.enable = lib.mkForce false;
      services.resolved.enable = lib.mkForce false;
      environment.etc."resolv.conf".text = lib.mkForce ''
        nameserver 10.70.10.1
        nameserver fd42:dead:feed:70::1
        options edns0
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
    extraModules = [
      ({ pkgs, ... }: {
        systemd.services.hostile-overlay-ipv6-source-fix = {
          description = "Prefer the hostile SLAAC GUA for overlay IPv6 egress";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" "nebula-runtime.service" ];
          wants = [ "network-online.target" "nebula-runtime.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = with pkgs; [
            bash
            coreutils
            gnugrep
            gawk
            iproute2
          ];
          script = ''
            set -euo pipefail

            gua=""
            for _ in $(seq 1 60); do
              gua="$(
                ip -6 -o addr show dev eth0 scope global \
                  | grep -v ' fd' \
                  | grep -v 'temporary' \
                  | head -n1 \
                  | awk '{ print $4 }'
              )"
              gua="''${gua%/*}"
              if [ -n "$gua" ]; then
                break
              fi
              sleep 1
            done

            if [ -z "$gua" ]; then
              echo "hostile-overlay-ipv6-source-fix: no global hostile GUA found on eth0 after waiting" >&2
              exit 1
            fi

            ip -6 route replace ::/1 via fd42:dead:beef:ee::254 dev nebula1 table 100 src "$gua"
            ip -6 route replace 8000::/1 via fd42:dead:beef:ee::254 dev nebula1 table 100 src "$gua"
          '';
        };
      })
    ];
  };

  storageClientContainer = {
    networkModule = mkDhcpNetworkModule;
    firewallModule = {
      networking.firewall.enable = true;
      networking.firewall.allowedUDPPorts = [ 4242 ];
    };
  };

  profileToModules = profile:
    if profile == "core-client" then
      coreClientContainer
    else if profile == "branch-web" then
      branchWebContainer
    else if profile == "hostile-exit" then
      hostileExitContainer
    else if profile == "storage-client" then
      storageClientContainer
    else
      throw "Unsupported overlay runtime node container profile: ${profile}";

  mkOverlayContainer = nodeName: nodeSpec:
    let
      containerSpec = nodeSpec.materialization.container or (throw "nebulaRuntimePlan.nodes.${nodeName}.materialization.container is required");
      profileSpec = profileToModules (containerSpec.profile or (throw "overlayRuntimeNodes.${nodeName}.container.profile is required"));
    in
    {
      autoStart = true;
      privateNetwork = true;
      enableTun = true;
      hostBridge = containerSpec.hostBridge or (throw "overlayRuntimeNodes.${nodeName}.container.hostBridge is required");
      bindMounts = mkNebulaProfileMount nodeName;

      config = mkNebulaNode {
        networkModule = profileSpec.networkModule;
        firewallModule = profileSpec.firewallModule or { };
        extraModules = profileSpec.extraModules or [ ];
      };
    };
in
lib.mapAttrs mkOverlayContainer (nebulaRuntimePlan.nodes or { })
