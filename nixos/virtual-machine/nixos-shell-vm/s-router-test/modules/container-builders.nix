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
    {
      systemd.tmpfiles.rules = [
        "d /persist/etc/nebula 0700 root root -"
      ];

      systemd.services.nebula-runtime = {
        description = "Runtime Nebula daemon for ${nodeName}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          ExecStartPre = "${pkgs.bash}/bin/bash -lc 'for _ in $(seq 1 120); do [ -s /persist/etc/nebula/config.yml ] && exit 0; sleep 1; done; exit 1'";
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

  mkNebulaNode =
    {
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
        (mkNebulaRuntimeService "overlay-node")
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
    mkNebulaNode
    mkNebulaProfileMount
    mkStaticTenantEndpoint
    mkTenantEndpoint
    ;
}
