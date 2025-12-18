{ pkgs, lib, ... }:
{

  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet filter {


      chain input {
      type filter hook input priority 0;
      policy drop;


      # Loopback
      iif lo accept


      # Established / related
      ct state established,related accept


      # --- ICMP ---
      ip protocol icmp accept
      ip6 nexthdr icmpv6 accept


      # --- DHCPv6 client (ISP) ---
      iifname "ppp0" udp sport 547 udp dport 546 accept




      # --- EXPLICIT DNS BLOCK ON WAN (LOG + DROP, VALID) ---
      iifname "ppp0" udp dport 53 log prefix "DROP_DNS_UDP_WAN: "
      iifname "ppp0" udp dport 53 drop


      iifname "ppp0" tcp dport 53 log prefix "DROP_DNS_TCP_WAN: "
      iifname "ppp0" tcp dport 53 drop


      # --- BLOCK ALL OTHER UDP FROM WAN ---
      iifname "ppp0" meta l4proto udp log prefix "DROP_UDP_WAN: "
      iifname "ppp0" meta l4proto udp drop


      # --- BLOCK ALL OTHER TCP FROM WAN ---
      iifname "ppp0" meta l4proto tcp log prefix "DROP_TCP_WAN: "
      iifname "ppp0" meta l4proto tcp drop
      }


      chain forward {
      type filter hook forward priority 0;
      policy drop;


      ct state established,related accept


      # OPNsense → WAN
      iifname "lan1010" oifname "ppp0" accept


      # WAN → OPNsense (stateful return)
      iifname "ppp0" oifname "lan1010" ct state established,related accept


      # LAN → WAN
      iifname { "lan2", "lan3", "lan10", "lan1000", "lan1010"} oifname "ppp0" accept


      # WAN → LAN denied
      iifname "ppp0" log prefix "DROP_FWD_PPP0: "
      iifname "ppp0" drop
      }


      chain output {
      type filter hook output priority 0;
      policy accept;
      }
      }
    '';
  };
  system.stateVersion = "25.11";

  services.dbus.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    dnsutils
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
    #"L+ /etc/resolv.conf - - - - /etc/ppp/resolv.conf"
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

  systemd.network.networks."30-lan1010" = {
    matchConfig.Name = "lan1010";

    networkConfig = {
      Address = "203.0.113.1/30";
    };

    routes = [
      {
        Destination = "203.0.113.0/30";
        Scope = "link";
      }
    ];
  };

  networking.nat = {
    enable = true;
    externalInterface = "ppp0";
    internalInterfaces = [
      "lan2"
      "lan3"
      "lan10"
      "lan1000"
      #"lan1010"
    ];
  };

  ############################
  # Kea DHCP-DDNS (FIXED)
  ############################
  services.kea.dhcp-ddns = {
    enable = true;

    settings = {
      DhcpDdns = {
        ip-address = "127.0.0.1";
        port = 53001;

        tsig-keys = [
          {
            name = "kea-ddns-key";
            algorithm = "hmac-sha256";
            digest-bits = 256;
            secret = "%{env:KEA_TSIG_SECRET}";
          }
        ];

        forward-ddns = {
          ddns-domains = [
            {
              name = "lan.";
              key-name = "kea-ddns-key";
              dns-servers = [
                {
                  ip-address = "127.0.0.1";
                  port = 53;
                }
              ];
            }
          ];
        };

        reverse-ddns = {
          ddns-domains = [
            {
              name = "168.192.in-addr.arpa.";
              key-name = "kea-ddns-key";
              dns-servers = [
                {
                  ip-address = "127.0.0.1";
                  port = 53;
                }
              ];
            }
          ];
        };
      };
    };
  };

  environment.etc."kea/kea-dhcp4.conf".text = ''
    {
      "Dhcp4": {
        "interfaces-config": {
          "interfaces": [ "lan2", "lan3", "lan10", "lan1000" ]
        },
        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/dhcp4.leases"
        },
        "ddns-qualifying-suffix": "lan.",
        "ddns-override-client-update": true,
        "ddns-override-no-update": true,

        "dhcp-ddns": {
           "enable-updates": true,
           "server-ip": "127.0.0.1",
           "server-port": 53001
        },
        "subnet4": [
          {
            "id": 1,
            "subnet": "192.168.1.0/24",
            "pools": [ { "pool": "192.168.1.100 - 192.168.1.200" } ],
            "option-data": [
              { "name": "routers", "data": "192.168.1.1" },
              { "name": "domain-name-servers", "data": "192.168.1.1, 1.1.1.1, 8.8.8.8" }
            ]
          },
          {
            "id": 2,
            "subnet": "192.168.3.0/24",
            "pools": [ { "pool": "192.168.3.100 - 192.168.3.200" } ],
            "option-data": [
              { "name": "routers", "data": "192.168.3.1" },
              { "name": "domain-name-servers", "data": "192.168.3.1" }
            ]
          },
          {
            "id": 3,
            "subnet": "192.168.10.0/24",
            "pools": [ { "pool": "192.168.10.100 - 192.168.10.200" } ],
            "option-data": [
              { "name": "routers", "data": "192.168.10.1" },
              { "name": "domain-name-servers", "data": "192.168.10.1, 1.1.1.1" }

            ]
          },
          {
            "id": 4,
            "subnet": "192.168.100.0/24",
            "pools": [ { "pool": "192.168.100.100 - 192.168.100.200" } ],
            "option-data": [
              { "name": "routers", "data": "192.168.100.1" },
              { "name": "domain-name-servers", "data": "192.168.100.1" }

            ]
          },
          {
            "id": 5,
            "subnet": "192.168.101.0/24",
            "pools": [ { "pool": "192.168.101.100 - 192.168.101.200" } ],
            "option-data": [
              { "name": "routers", "data": "192.168.101.1" },
              { "name": "domain-name-servers", "data": "192.168.101.1" }
            ]
          }
        ]
      }
    }
  '';
  systemd.services.kea-tsig-init = {
    description = "Generate TSIG key for Kea DDNS if missing";

    wantedBy = [ "multi-user.target" ];
    before = [
      "kea-dhcp-ddns.service"
      "unbound.service"
    ];

    path = [
      pkgs.bind
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "init-kea-tsig" ''
        set -euo pipefail
        KEY=/var/lib/kea/tsig.key
        ENV=/var/lib/kea/tsig.env

        if [ ! -f "$KEY" ]; then
          tsig-keygen kea-ddns-key \
            | sed -n 's/.*secret "\(.*\)".*/\1/p' \
            > "$KEY"
          chmod 600 "$KEY"
        fi

        echo "KEA_TSIG_SECRET=$(cat "$KEY")" > "$ENV"
        chmod 600 "$ENV"
      '';
    };
  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "dhcpcd-ipv6.service" ];
    serviceConfig.ExecStart = "${pkgs.radvd}/bin/radvd -n -d 5 -C /etc/radvd.conf";
  };

  environment.etc."radvd.conf".text = ''
    interface lan2 {
      AdvSendAdvert on;
      prefix ::/64 { AdvOnLink on; AdvAutonomous on; };
    };

    interface lan3 {
      AdvSendAdvert on;
      prefix ::/64 { AdvOnLink on; AdvAutonomous on; };
    };

    interface lan10 {
      AdvSendAdvert on;
      prefix ::/64 { AdvOnLink on; AdvAutonomous on; };
    };

    interface lan1000 {
      AdvSendAdvert on;
      prefix ::/64 { AdvOnLink on; AdvAutonomous on; };
    };
  '';

  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 Server";
    wantedBy = [ "multi-user.target" ];

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.systemd
      pkgs.kea
      pkgs.gnugrep
    ];

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
        set -euo pipefail
        set -x

        mkdir -p /run/kea || true 
        mkdir -p /var/lib/kea || true
        chmod 0755 /run/kea

        exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
      '';

      Restart = "always";
      RestartSec = 20;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        set -euo pipefail
        set -x
        LOG=$(journalctl -u kea-dhcp4 -b --since "$(systemctl show kea-dhcp4 -p InactiveEnterTimestamp --value)")

        if ! echo "$LOG" | grep -q "listening on interface"; then
          echo "kea-dhcp4 not listening on any interface"
          exit 1
        fi

        sleep 3
        LOG=$(journalctl -u kea-dhcp4 -b --since "$(systemctl show kea-dhcp4 -p InactiveEnterTimestamp --value)")
        if echo "$LOG" | grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
          echo "kea-dhcp4 failed to open sockets"
          exit 1
        fi
      '';
    };

  };

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = [
          "127.0.0.1"
          "0.0.0.0"
          "::1"
          "::0"
        ];

        access-control = [
          "127.0.0.1 allow"
          "192.168.0.0/16 allow"
          "10.0.0.0/8 allow"
          "172.16.0.0/12 allow"
          "fd00::/8 allow"
        ];

        local-zone = [
          "lan. transparent"
          "168.192.in-addr.arpa. transparent"
        ];
      };

      #key = [
      #  {
      #    name = "kea-ddns-key";
      #    algorithm = "hmac-sha256";
      #    secret = "%{env:KEA_TSIG_SECRET}";
      #  }
      #];
    };
  };

  systemd.services.unbound = {
    after = [ "kea-tsig-init.service" ];
    wants = [ "kea-tsig-init.service" ];
    serviceConfig.EnvironmentFile = "-/var/lib/kea/tsig.env";
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
    ipv6only

    interface ppp0
      iaid 1
      ia_pd 1 lan2/0/64 lan3/1/64 lan10/2/64 lan1000/3/64 

  '';

  environment.etc."ppp/pap-secrets" = {
    mode = "0600";
    text = ''
      "${builtins.readFile /run/secrets/pppoe-username}" * "${builtins.readFile /run/secrets/pppoe-password}" *
    '';
  };
  environment.etc."ppp/peers/pppoe-wan" = {
    mode = "0600";
    text = ''
      plugin pppoe.so
      nic-wan

      user "${builtins.readFile /run/secrets/pppoe-username}"

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

  systemd.services.kea-dhcp-ddns.serviceConfig.EnvironmentFile = "-/var/lib/kea/tsig.env";

  systemd.services.kea-dhcp-ddns.after = [ "kea-tsig-init.service" ];
  systemd.services.kea-dhcp-ddns.wants = [ "kea-tsig-init.service" ];

  environment.etc."NetworkManager/system-connections/isp-pppoe.nmconnection" = {
    mode = "0600";
    text = ''
      [connection]
      id=pppoe-wan
      type=pppoe
      interface-name=wan

      [pppoe]
      username=${builtins.readFile /run/secrets/pppoe-username}
      password=${builtins.readFile /run/secrets/pppoe-password}

      [ipv4]
      method=auto

      [ipv6]
      method=disabled
    '';
  };

}
