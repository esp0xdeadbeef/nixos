{ pkgs, lib, ... }:
{
  services.kea.dhcp-ddns = {
    enable = true;

    settings = {
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
              { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8, 192.168.1.1" }
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

  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 Server";
    wantedBy = [ "multi-user.target" ];

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.systemd
      pkgs.kea
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.gawk
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
      RestartSec = 10;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        #!/usr/bin/env bash
        set -euo pipefail

        sleep 1
        REQUIRED_IFACES=(lan2 lan3 lan10 lan1000)

        for i in ''${REQUIRED_IFACES[@]}; do
          ip="$(ip -4 addr show dev "$i" | awk '/inet / {print $2}' | cut -d/ -f1)"
          if ! ss -lunp | grep -q "$ip:67"; then
            echo "kea-dhcp4 not listening on $i ($ip)"
            exit 1
          fi
        done
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
    };
  };

  systemd.services.unbound = {
    after = [ "kea-tsig-init.service" ];
    wants = [ "kea-tsig-init.service" ];
    serviceConfig.EnvironmentFile = "-/var/lib/kea/tsig.env";
  };
}
