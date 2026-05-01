{ lib, pkgs }:

let
  mkTenantEndpoint =
    bridge:
    { pkgs, ... }:
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

      environment.systemPackages = [
        pkgs.bind
        pkgs.curl
        pkgs.iproute2
        pkgs.iputils
        pkgs.traceroute
      ];
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
    {
      pkgs,
      lib,
      ...
    }@moduleArgs:
    let
      evaluatedExtraModules = map (
        module: if builtins.isFunction module then module moduleArgs else module
      ) extraModules;
      hostnameModule =
        lib.optional (hostname != null) {
          networking.hostName = hostname;
        };
    in
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

          environment.systemPackages = [
            pkgs.avahi
            pkgs.bind
            pkgs.curl
            pkgs.iproute2
            pkgs.iputils
            pkgs.traceroute
          ];

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
      ++ hostnameModule
      ++ evaluatedExtraModules
    );

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
    {
      pkgs,
      lib,
      ...
    }@moduleArgs:
    let
      dmz4 = "10.20.30.0/24";
      dmz6 = "fd42:dead:beef:30::/64";
      evaluatedExtraModules = map (
        module: if builtins.isFunction module then module moduleArgs else module
      ) extraModules;
      renderPortSet =
        ports:
        if ports == [ ] then "" else "{ ${lib.concatStringsSep ", " (map builtins.toString ports)} }";
      tcpSet = renderPortSet allowedTcpPorts;
      udpSet = renderPortSet allowedUdpPorts;
      serviceRules =
        lib.concatStringsSep "\n" (
          (lib.optionals (allowedTcpPorts != [ ]) [
            "      ip saddr != ${dmz4} tcp dport ${tcpSet} accept"
            "      ip6 saddr != ${dmz6} tcp dport ${tcpSet} accept"
          ])
          ++ (lib.optionals (allowedUdpPorts != [ ]) [
            "      ip saddr != ${dmz4} udp dport ${udpSet} accept"
            "      ip6 saddr != ${dmz6} udp dport ${udpSet} accept"
          ])
        );
    in
    lib.mkMerge (
      [
        {
          system.stateVersion = "25.11";

          networking.useNetworkd = true;
          systemd.network.enable = true;
          networking.useDHCP = false;
          networking.useHostResolvConf = false;
          services.resolved.enable = true;
          networking.firewall.enable = lib.mkForce false;

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

          environment.systemPackages = [
            pkgs.bind
            pkgs.curl
            pkgs.iproute2
            pkgs.iputils
            pkgs.netcat-openbsd
            pkgs.socat
            pkgs.tcpdump
            pkgs.traceroute
          ];

          networking.nftables.enable = true;
          networking.nftables.ruleset = ''
            table inet endpoint {
              chain input {
                type filter hook input priority filter; policy drop;
                iifname "lo" accept
                ct state established,related accept
          ${serviceRules}
              }

              chain forward {
                type filter hook forward priority filter; policy drop;
              }

              chain output {
                type filter hook output priority filter; policy drop;
                oifname "lo" accept
                ct state established,related accept
                ip daddr ${dmz4} accept
                ip6 daddr ${dmz6} accept
              }
            }
          '';
        }
      ]
      ++ evaluatedExtraModules
    );

  mkNebulaRuntimeService =
    nodeName:
    {
      pkgs,
      ...
    }:
    let
      prepareUnderlayRoutes = pkgs.writeShellScript "nebula-runtime-prepare-underlay-routes-${nodeName}" ''
        set -euo pipefail
        export PATH=${
          lib.makeBinPath [
            pkgs.coreutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.gnused
            pkgs.iproute2
          ]
        }:$PATH

        config="/persist/etc/nebula/config.yml"
        [ -s "$config" ] || exit 1

        ip route del 0.0.0.0/1 dev nebula1 2>/dev/null || true
        ip route del 128.0.0.0/1 dev nebula1 2>/dev/null || true
        ip -6 route del ::/1 dev nebula1 2>/dev/null || true
        ip -6 route del 8000::/1 dev nebula1 2>/dev/null || true

        overlay_hosts="$(
          grep -E '^[[:space:]]*-[[:space:]]*"[^"]+"' "$config" \
            | sed -E 's/^[[:space:]]*-[[:space:]]*"([^"]+)".*/\1/' \
            | grep -Ev '^(\[[^]]+\]:[0-9]+|[^:]+:[0-9]+)$' \
            | grep -v '^$' \
            | sort -u
        )"

        for host in $overlay_hosts; do
          if printf '%s' "$host" | grep -q ':'; then
            ip -6 route del "$host/128" 2>/dev/null || true
          else
            ip route del "$host/32" 2>/dev/null || true
          fi
        done

        endpoint_hosts="$(
          grep -E '^[[:space:]]*-[[:space:]]*"[^"]+"' "$config" \
            | sed -E 's/^[[:space:]]*-[[:space:]]*"([^"]+)".*/\1/' \
            | grep -E '^(\[[^]]+\]:[0-9]+|[^:]+:[0-9]+)$' \
            | sed -E 's/^\[([^]]+)\]:[0-9]+$/\1/; s/^([^:]+):[0-9]+$/\1/' \
            | grep -v '^$' \
            | sort -u
        )"

        for endpoint in $endpoint_hosts; do
          if printf '%s' "$endpoint" | grep -q ':'; then
            route="$(ip -6 route get "$endpoint" 2>/dev/null || true)"
            dev="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
            via="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
            if [ -n "$dev" ] && [ -n "$via" ]; then
              ip -6 route replace "$endpoint/128" via "$via" dev "$dev"
            elif [ -n "$dev" ]; then
              ip -6 route replace "$endpoint/128" dev "$dev"
            fi
          else
            route="$(ip -4 route get "$endpoint" 2>/dev/null || true)"
            dev="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')"
            via="$(printf '%s\n' "$route" | awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
            if [ -n "$dev" ] && [ -n "$via" ]; then
              ip route replace "$endpoint/32" via "$via" dev "$dev"
            elif [ -n "$dev" ]; then
              ip route replace "$endpoint/32" dev "$dev"
            fi
          fi
        done
      '';
    in
    {
      systemd.tmpfiles.rules = [
        "d /persist/etc/nebula 0700 root root -"
      ];

      systemd.services.nebula-runtime = {
        description = "Runtime Nebula daemon for ${nodeName}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStartPre = [
            "${pkgs.bash}/bin/bash -lc 'for _ in $(seq 1 120); do [ -s /persist/etc/nebula/config.yml ] && exit 0; sleep 1; done; exit 1'"
            "${prepareUnderlayRoutes}"
          ];
          ExecStart = "${pkgs.nebula}/bin/nebula -config /persist/etc/nebula/config.yml";
          Restart = "always";
          RestartSec = 2;
          AmbientCapabilities = [
            "CAP_NET_ADMIN"
            "CAP_NET_BIND_SERVICE"
          ];
          CapabilityBoundingSet = [
            "CAP_NET_ADMIN"
            "CAP_NET_BIND_SERVICE"
          ];
        };
      };
    };

  mkNebulaRuntimeAddon =
    {
      nodeName,
      firewallModule ? { },
      extraModules ? [ ],
    }:
    {
      pkgs,
      ...
    }:
    {
      imports = extraModules ++ [
        firewallModule
        (mkNebulaRuntimeService nodeName)
      ];

      systemd.network.wait-online.enable = false;

      environment.systemPackages = with pkgs; [
        bind
        curl
        iproute2
        iputils
        jq
        nebula
        netcat-openbsd
        tcpdump
        traceroute
      ];
    };

  mkNebulaNode =
    {
      nodeName ? "overlay-node",
      networkModule,
      firewallModule ? { },
      extraModules ? [ ],
    }:
    {
      pkgs,
      ...
    }:
    {
      system.stateVersion = "25.11";

      imports = extraModules ++ [
        networkModule
        firewallModule
        (mkNebulaRuntimeService nodeName)
      ];

      networking.useNetworkd = true;
      systemd.network.enable = true;
      systemd.network.wait-online.enable = false;
      networking.useDHCP = false;
      networking.useHostResolvConf = false;
      services.resolved.enable = true;

      environment.systemPackages = with pkgs; [
        bind
        curl
        iproute2
        iputils
        jq
        nebula
        netcat-openbsd
        tcpdump
        traceroute
      ];
    };

  mkNebulaProfileMount = profileName: {
    "/persist/etc/nebula" = {
      hostPath = "/persist/nebula-runtime/profiles/${profileName}";
      isReadOnly = false;
    };
  };
in
{
  inherit
    mkDmzEndpoint
    mkNebulaRuntimeAddon
    mkNebulaNode
    mkNebulaProfileMount
    mkStaticTenantEndpoint
    mkTenantEndpoint
    ;
}
