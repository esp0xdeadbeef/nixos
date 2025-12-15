{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "ens21";
  wanIf = "ens19";

  natVlans = [
    2
    3
    10
    1000
    1010
  ];
  wanVlan = 6;
in
{
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  networking = {
    interfaces.ens20 = {
      ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens20";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
  };
  #boot.kernel.sysctl = {
  #  "net.ipv4.ip_forward" = 1;
  #  # IPv6 routing ON
  #  "net.ipv6.conf.all.forwarding" = 1;
  #  "net.ipv6.conf.default.forwarding" = 1;

  #  # REQUIRED for RA while forwarding
  #  "net.ipv6.conf.all.accept_ra" = 2;
  #  "net.ipv6.conf.default.accept_ra" = 2;

  #  # LAN interfaces MUST accept RA
  #  "net.ipv6.conf.lan2.accept_ra" = 2;
  #  "net.ipv6.conf.lan3.accept_ra" = 2;
  #  "net.ipv6.conf.lan10.accept_ra" = 2;
  #  "net.ipv6.conf.lan1000.accept_ra" = 2;
  #  "net.ipv6.conf.lan1010.accept_ra" = 2;

  #  # RA over bridges WILL NOT WORK without this
  #  "net.bridge.bridge-nf-call-ip6tables" = 0;
  #  "net.bridge.bridge-nf-call-iptables" = 0;
  #  "net.bridge.bridge-nf-call-arptables" = 0;
  #};

  systemd.network.netdevs =
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "${lanIf}.${toString id}";
          Kind = "vlan";
        };
        vlanConfig.Id = id;
      }
    )
    // lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "br-vlan${toString id}";
          Kind = "bridge";
        };
      }
    )
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
        LinkLocalAddressing = "no";
        VLAN = map (v: "${lanIf}.${toString v}") natVlans;
      };
    };

    "40-${wanIf}" = {
      matchConfig.Name = wanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
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
      v = lib.toInt (lib.last (lib.splitString "." name));
    in
    {
      matchConfig.Name = "${lanIf}.${toString v}";
      networkConfig.Bridge = "br-vlan${toString v}";
    }
  )
  // lib.genAttrs (map (v: "60-br-vlan${toString v}") natVlans) (
    name:
    let
      v = lib.toInt (lib.last (lib.splitString "vlan" name));
    in
    {
      matchConfig.Name = "br-vlan${toString v}";
      networkConfig.ConfigureWithoutCarrier = true;
    }
  )
  // {
    "60-br-wan${toString wanVlan}" = {
      matchConfig.Name = "br-wan${toString wanVlan}";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };

  containers.pppoe-test = {
    autoStart = true;
    privateNetwork = true;

    extraVeths =
      lib.genAttrs (map (v: "lan${toString v}") natVlans) (
        name:
        let
          v = lib.toInt (lib.removePrefix "lan" name);
        in
        {
          hostBridge = "br-vlan${toString v}";
        }
      )
      // {
        wan.hostBridge = "br-wan${toString wanVlan}";
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
      { pkgs, lib, ... }:
      {

        system.stateVersion = "25.11";

        services.dbus.enable = true;

        environment.systemPackages = with pkgs; [
          radvd
          dhcpcd
          networkmanager
          ppp
          iproute2
          tcpdump
          kea
        ];

        systemd.tmpfiles.rules = [
          #"L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf"
          "L+ /etc/resolv.conf - - - - /etc/ppp/resolv.conf"
          "d /run/kea 0777 root root -"
          "d /var/lib/kea 0777 root root -"
          "d /etc/ppp/peers/ 0777 root root -"
        ];

        systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

        networking.useHostResolvConf = lib.mkForce false;

        networking.useNetworkd = true;

        #networking.networkmanager = {
        #  enable = true;
        #  dns = "default";
        #};

        #networking.networkmanager.enable = true;
        networking.useDHCP = false;

        networking.interfaces = {
          lan2.ipv4.addresses = [
            {
              address = "192.168.1.1";
              prefixLength = 24;
            }
          ];
          lan3.ipv4.addresses = [
            {
              address = "192.168.3.1";
              prefixLength = 24;
            }
          ];
          lan10.ipv4.addresses = [
            {
              address = "192.168.10.1";
              prefixLength = 24;
            }
          ];
          lan1000.ipv4.addresses = [
            {
              address = "192.168.100.1";
              prefixLength = 24;
            }
          ];
          lan1010.ipv4.addresses = [
            {
              address = "192.168.101.1";
              prefixLength = 24;
            }
          ];
        };

        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;

          # accept RA from ppp0
          "net.ipv6.conf.ppp0.accept_ra" = 2;

          # IPv6 routing ON
          "net.ipv6.conf.all.forwarding" = 1;
          "net.ipv6.conf.default.forwarding" = 1;

          # REQUIRED for RA while forwarding
          "net.ipv6.conf.all.accept_ra" = 2;
          "net.ipv6.conf.default.accept_ra" = 2;

          # LAN interfaces MUST accept RA
          "net.ipv6.conf.lan2.accept_ra" = 2;
          "net.ipv6.conf.lan3.accept_ra" = 2;
          "net.ipv6.conf.lan10.accept_ra" = 2;
          "net.ipv6.conf.lan1000.accept_ra" = 2;
          "net.ipv6.conf.lan1010.accept_ra" = 2;

          # RA over bridges WILL NOT WORK without this
          "net.bridge.bridge-nf-call-ip6tables" = 0;
          "net.bridge.bridge-nf-call-iptables" = 0;
          "net.bridge.bridge-nf-call-arptables" = 0;
        };

        networking.nat = {
          enable = true;
          externalInterface = "ppp0";
          internalInterfaces = [
            "lan2"
            "lan3"
            "lan10"
            "lan1000"
            "lan1010"
          ];
        };

        environment.etc."kea/kea-dhcp4.conf".text = ''
          {
            "Dhcp4": {
              "interfaces-config": {
                "interfaces": [ "lan2", "lan3", "lan10", "lan1000", "lan1010" ]
              },
              "lease-database": {
                "type": "memfile",
                "persist": true,
                "name": "/var/lib/kea/dhcp4.leases"
              },
              "subnet4": [
                {
                  "id": 1,
                  "subnet": "192.168.1.0/24",
                  "pools": [ { "pool": "192.168.1.100 - 192.168.1.200" } ],
                  "option-data": [
                    { "name": "routers", "data": "192.168.1.1" },
                    { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                  ]
                },
                {
                  "id": 2,
                  "subnet": "192.168.3.0/24",
                  "pools": [ { "pool": "192.168.3.100 - 192.168.3.200" } ],
                  "option-data": [
                    { "name": "routers", "data": "192.168.3.1" },
                    { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                  ]
                },
                {
                  "id": 3,
                  "subnet": "192.168.10.0/24",
                  "pools": [ { "pool": "192.168.10.100 - 192.168.10.200" } ],
                  "option-data": [
                    { "name": "routers", "data": "192.168.10.1" },
                    { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                  ]
                },
                {
                  "id": 4,
                  "subnet": "192.168.100.0/24",
                  "pools": [ { "pool": "192.168.100.100 - 192.168.100.200" } ],
                  "option-data": [
                    { "name": "routers", "data": "192.168.100.1" },
                    { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                  ]
                },
                {
                  "id": 5,
                  "subnet": "192.168.101.0/24",
                  "pools": [ { "pool": "192.168.101.100 - 192.168.101.200" } ],
                  "option-data": [
                    { "name": "routers", "data": "192.168.101.1" },
                    { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
                  ]
                }
              ]
            }
          }
        '';

        systemd.services.radvd = {
          wantedBy = [ "multi-user.target" ];
          after = [ "dhcpcd-ipv6.service" ];
          serviceConfig.ExecStart = "${pkgs.radvd}/bin/radvd -n -d 5 -C /etc/radvd.conf";
        };

        environment.etc."radvd.conf".text = ''
          interface lan2 { AdvSendAdvert on; };
          interface lan3 { AdvSendAdvert on; };
          interface lan10 { AdvSendAdvert on; };
          interface lan1000 { AdvSendAdvert on; };
          interface lan1010 { AdvSendAdvert on; };
        '';

        systemd.services.kea-dhcp4 = {
          description = "Kea DHCPv4 Server";
          wantedBy = [ "multi-user.target" ];

          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
              set -euo pipefail
              set -x

              mkdir -p /run/kea || true 
              mkdir -p /var/lib/kea || true
              chmod 0755 /run/kea

              exec ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
            '';

            Restart = "always";
            RestartSec = 2;
            ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
              set -euo pipefail
              LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 | tail -n 40)"

              if ! echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "listening on interface"; then
                echo "kea-dhcp4 not listening on any interface"
                exit 1
              fi

              sleep 3
              LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"
              if echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
                echo "kea-dhcp4 failed to open sockets"
                exit 1
              fi
            '';
          };

        };

        systemd.services.pppoe-pap = {
          description = "ppp connection service";
          wantedBy = [ "multi-user.target" ];

          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.ppp
            pkgs.networkmanager
          ];

          serviceConfig = {
            ExecStart = pkgs.writeShellScript "ppp-connect" ''
              set -euo pipefail
              set -x
              #nmcli connection down pppoe-wan
              pppd call pppoe-wan nodetach debug
            '';

            Restart = "always";
            RestartSec = 2;
          };
        };

        systemd.services.dhcpcd-ipv6 = {
          description = "DHCPv6-PD client";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -w -d -f /etc/dhcpcd.conf ppp0";
            Restart = "always";
            RestartSec = 2;
          };
        };
        environment.etc."dhcpcd.conf".text = ''
          duid
          persistent
          noipv6rs
          noipv4

          interface ppp0
            iaid 1
            ia_pd 1

          interface lan2
            ia_pd 1/64

          interface lan3
            ia_pd 1/64

          interface lan10
            ia_pd 1/64

          interface lan1000
            ia_pd 1/64

          interface lan1010
            ia_pd 1/64
        '';

        environment.etc."ppp/pap-secrets" = {
          mode = "0600";
          text = ''
            "${builtins.readFile config.sops.secrets.pppoe-username.path}" * "${builtins.readFile config.sops.secrets.pppoe-password.path}" *
          '';
        };
        environment.etc."ppp/peers/pppoe-wan" = {
          mode = "0600";
          text = ''
            plugin pppoe.so
            nic-wan

            user "${builtins.readFile config.sops.secrets.pppoe-username.path}"

            # --- AUTH ---
            noauth              # never require peer authentication
            refuse-chap
            refuse-mschap
            refuse-mschap-v2
            refuse-eap
            # NOTE: no +pap

            # --- ROUTING ---
            defaultroute
            persist

            # --- IPv6 ---
            +ipv6
            ipv6cp-accept-local
            ipv6cp-accept-remote

            mtu 1492
            mru 1492

          '';
        };
        environment.etc."NetworkManager/system-connections/isp-pppoe.nmconnection" = {
          mode = "0600";
          text = ''
            [connection]
            id=pppoe-wan
            type=pppoe
            interface-name=wan

            [pppoe]
            #username=/run/secrets/pppoe-username
            username=${builtins.readFile config.sops.secrets.pppoe-username.path}
            #password=/run/secrets/pppoe-password
            password=${builtins.readFile config.sops.secrets.pppoe-password.path}

            [ipv4]
            method=auto

            [ipv6]
            method=disabled
          '';
        };

      };

  };
}
