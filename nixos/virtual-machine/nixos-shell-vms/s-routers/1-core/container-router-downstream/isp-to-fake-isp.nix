{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "ens21";
  wanIf = "ens19";

  # Downstream “fake ISP” segments
  natVlans = [
    90
    91
  ];

  # ISP VLAN (if your upstream is tagged)
  wanVlan = 6;
in
{
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ############################################
  # HOST: VLANs + Bridges
  ############################################

  systemd.network.netdevs =
    # LAN VLAN devices (ens21.<vid>)
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (
      name:
      let
        vid = lib.toInt (lib.removePrefix "10-${lanIf}-vlan" name);
      in
      {
        netdevConfig = {
          Name = "${lanIf}.${toString vid}";
          Kind = "vlan";
        };
        vlanConfig.Id = vid;
      }
    )
    # Bridges per VLAN
    // lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (
      name:
      let
        vid = lib.toInt (lib.removePrefix "20-br-vlan" name);
      in
      {
        netdevConfig = {
          Name = "br-vlan${toString vid}";
          Kind = "bridge";
        };
      }
    )
    # WAN VLAN + bridge
    // {
      "10-${wanIf}-vlan${toString wanVlan}" = {
        netdevConfig = {
          Name = "${wanIf}.${toString wanVlan}";
          Kind = "vlan";
        };
        vlanConfig.Id = wanVlan;
      };

      "20-br-wan${toString wanVlan}" = {
        netdevConfig = {
          Name = "br-wan${toString wanVlan}";
          Kind = "bridge";
        };
      };
    };

  systemd.network.networks = {
    "20-${lanIf}" = {
      matchConfig.Name = lanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        VLAN = map (v: "${lanIf}.${toString v}") natVlans;
      };
    };

    "40-${wanIf}" = {
      matchConfig.Name = wanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        VLAN = [ "${wanIf}.${toString wanVlan}" ];
      };
    };

    "50-${wanIf}.${toString wanVlan}" = {
      matchConfig.Name = "${wanIf}.${toString wanVlan}";
      networkConfig.Bridge = "br-wan${toString wanVlan}";
    };
  }
  // lib.genAttrs (map (v: "30-${lanIf}.${toString v}") natVlans) (
    name:
    let
      vid = lib.toInt (lib.removePrefix "30-${lanIf}." name);
    in
    {
      matchConfig.Name = "${lanIf}.${toString vid}";
      networkConfig.Bridge = "br-vlan${toString vid}";
    }
  )
  // lib.genAttrs (map (v: "60-br-vlan${toString v}") natVlans) (
    name:
    let
      vid = lib.toInt (lib.removePrefix "60-br-vlan" name);
    in
    {
      matchConfig.Name = "br-vlan${toString vid}";
      networkConfig.ConfigureWithoutCarrier = true;
    }
  )
  // {
    "60-br-wan${toString wanVlan}" = {
      matchConfig.Name = "br-wan${toString wanVlan}";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };

  ############################################
  # CONTAINER: PPPoE terminator + PD server
  ############################################

  containers.pppoe-test = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      # Upstream ISP L2 (tagged VLAN 6 bridged by host)
      wan.hostBridge = "br-wan${toString wanVlan}";

      # Downstream “fake ISP” segments
      lan90.hostBridge = "br-vlan90";
      lan91.hostBridge = "br-vlan91";
    };

    allowedDevices = [
      {
        node = "/dev/ppp";
        modifier = "rw";
      }
    ];

    bindMounts = {
      "/dev/ppp" = {
        hostPath = "/dev/ppp";
        isReadOnly = false;
      };

      "/run/secrets/pppoe-username" = {
        hostPath = config.sops.secrets.pppoe-username.path;
        isReadOnly = true;
      };
      "/run/secrets/pppoe-password" = {
        hostPath = config.sops.secrets.pppoe-password.path;
        isReadOnly = true;
      };
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    config =
      {
        config,
        pkgs,
        lib,
        ...
      }:

      let
        # Generate Kea DHCPv6 config from the currently delegated ISP prefix
        genKeaPd = pkgs.writeShellScript "gen-kea-pd.sh" ''
                  set -euo pipefail

                  # Find an upstream *delegated* prefix present on ppp0.
                  # dhcpcd usually installs a route for the delegated prefix.
                  PARENT_PREFIX="$(
                    ip -6 route show dev ppp0 \
                      | awk '($1 ~ /^[0-9a-fA-F:]+\/[0-9]+$/) && ($1 !~ /^fe80:/) { print $1; exit }'
                  )"

                  if [ -z "$PARENT_PREFIX" ]; then
                    echo "[pd-edge] No delegated prefix route on ppp0 yet"
                    exit 0
                  fi

                  # Carve two non-overlapping /60s from the parent.
                  # If ISP gives /48, these become xxxx:xxxx:xxxx:7000::/60 and :7100::/60.
                  OPNSENSE_PD="$(${pkgs.ipv6calc}/bin/ipv6calc --action prefixadd --inprefix "$PARENT_PREFIX" --addprefix 7000::/60)"
                  NIXOS_PD="$(${pkgs.ipv6calc}/bin/ipv6calc --action prefixadd --inprefix "$PARENT_PREFIX" --addprefix 7100::/60)"

                  mkdir -p /run/kea

                  cat > /run/kea/kea-dhcp6.conf <<EOF
          {
            "Dhcp6": {
              "interfaces-config": { "interfaces": [ "lan90", "lan91" ] },

              "subnet6": [
                {
                  "subnet": "fd00:ffff:90::/64",
                  "pools": [ { "pool": "fd00:ffff:90::100 - fd00:ffff:90::1fff" } ],
                  "pd-pools": [ { "prefix": "$OPNSENSE_PD", "prefix-len": 60, "delegated-len": 64 } ]
                },
                {
                  "subnet": "fd00:ffff:91::/64",
                  "pools": [ { "pool": "fd00:ffff:91::100 - fd00:ffff:91::1fff" } ],
                  "pd-pools": [ { "prefix": "$NIXOS_PD", "prefix-len": 60, "delegated-len": 64 } ]
                }
              ]
            }
          }
          EOF

                  systemctl try-reload-or-restart kea-dhcp6.service
                  echo "[pd-edge] Updated Kea PD pools from $PARENT_PREFIX"
        '';

        # Generate /etc/ppp/pap-secrets + peers file at runtime from /run/secrets
        genPppFiles = pkgs.writeShellScript "gen-ppp-files.sh" ''
                  set -euo pipefail

                  USER="$(cat /run/secrets/pppoe-username)"
                  PASS="$(cat /run/secrets/pppoe-password)"

                  mkdir -p /etc/ppp/peers

                  cat > /etc/ppp/pap-secrets <<EOF
          "$USER" * "$PASS" *
          EOF
                  chmod 0600 /etc/ppp/pap-secrets

                  cat > /etc/ppp/peers/pppoe-wan <<'EOF'
          plugin rp-pppoe.so
          nic-wan

          # username is provided via "user" option below
          noauth
          defaultroute
          persist
          maxfail 0

          # IPv6 over PPP
          +ipv6
          ipv6cp-accept-local
          ipv6cp-accept-remote

          mtu 1492
          mru 1492
          EOF

                  # inject user line (can’t safely single-quote heredoc with runtime var)
                  sed -i "1i user \"$USER\"" /etc/ppp/peers/pppoe-wan
                  chmod 0600 /etc/ppp/peers/pppoe-wan
        '';
      in
      {
        services.resolved.enable = false;

        networking.useNetworkd = true;
        networking.networkmanager.enable = false;
        systemd.network.enable = true;
        networking.useDHCP = false;

        environment.systemPackages = with pkgs; [
          iproute2
          tcpdump
          ppp
          dhcpcd
          kea
          ipv6calc
        ];

        systemd.tmpfiles.rules = [
          "d /run/kea 0755 root root -"
          "d /var/lib/kea 0755 root root -"
          "d /etc/ppp/peers 0755 root root -"
        ];

        # Bring up the downstream “fake ISP” links in the container
        systemd.network.networks = {
          "10-wan-raw" = {
            matchConfig.Name = "wan";
            networkConfig = {
              DHCP = "no";
              IPv6AcceptRA = false;
            };
          };

          "20-lan90" = {
            matchConfig.Name = "lan90";
            networkConfig = {
              Address = "fd00:ffff:90::1/64";
              IPv6AcceptRA = false;
            };
          };

          "20-lan91" = {
            matchConfig.Name = "lan91";
            networkConfig = {
              Address = "fd00:ffff:91::1/64";
              IPv6AcceptRA = false;
            };
          };
        };

        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
          "net.ipv6.conf.default.forwarding" = 1;

          # allow accepting RA on ppp0 if needed
          "net.ipv6.conf.ppp0.accept_ra" = 2;
          "net.ipv6.conf.all.accept_ra" = 2;
          "net.ipv6.conf.default.accept_ra" = 2;
        };

        ############################################
        # PPPoE: generate files then run pppd
        ############################################

        systemd.services.pppoe-init = {
          description = "Generate PPPoE config from secrets";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = genPppFiles;
          };
        };

        systemd.services.pppoe = {
          description = "PPPoE session (ppp0)";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network-online.target"
            "pppoe-init.service"
          ];
          wants = [
            "network-online.target"
            "pppoe-init.service"
          ];
          path = [
            pkgs.ppp
            pkgs.iproute2
          ];
          serviceConfig = {
            ExecStart = pkgs.writeShellScript "pppoe-start" ''
              set -euo pipefail
              exec pppd call pppoe-wan nodetach debug
            '';
            Restart = "always";
            RestartSec = 2;
          };
        };

        ############################################
        # DHCPv6-PD client on ppp0 (ISP -> container)
        ############################################

        systemd.services.dhcpcd-ipv6 = {
          description = "DHCPv6-PD client on ppp0";
          wantedBy = [ "multi-user.target" ];
          after = [ "pppoe.service" ];
          wants = [ "pppoe.service" ];
          serviceConfig = {
            ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -w -d -f /etc/dhcpcd.conf ppp0";
            Restart = "always";
            RestartSec = 2;
          };
        };

        # IMPORTANT: here we request PD, but we do NOT assign it to lan90/lan91 directly.
        # We only need the delegated prefix present so gen-kea-pd can carve it up for Kea.
        environment.etc."dhcpcd.conf".text = ''
          duid
          persistent
          noipv6rs
          noipv4
          ipv6only

          interface ppp0
            iaid 1
            ia_pd 1
        '';

        ############################################
        # Kea DHCPv6 server (container -> downstream routers)
        ############################################

        services.kea.dhcp6 = {
          enable = true;
          configFile = "/run/kea/kea-dhcp6.conf";
        };

        systemd.services.gen-kea-pd = {
          description = "Generate Kea DHCPv6-PD pools from ISP delegated prefix";
          wantedBy = [ "multi-user.target" ];
          after = [ "dhcpcd-ipv6.service" ];
          wants = [ "dhcpcd-ipv6.service" ];
          before = [ "kea-dhcp6.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = genKeaPd;
          };
        };

        systemd.services.kea-dhcp6 = {
          requires = [ "gen-kea-pd.service" ];
          after = [ "gen-kea-pd.service" ];
        };

        systemd.timers.gen-kea-pd = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "45s";
            OnUnitActiveSec = "60s";
            AccuracySec = "10s";
          };
        };

        ############################################
        # Firewall (allow DHCPv6 server/client)
        ############################################
        networking.firewall.enable = true;
        networking.firewall.allowedUDPPorts = [
          546
          547
        ];
      };
  };
}
