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

  environment.etc."kea/kea-dhcp4.conf.tmp".text = ''
    {
      "Dhcp4": {
        "interfaces-config": {
          "interfaces": [ "lan7" ]
          // "interfaces": [ "lan2", "lan3", "lan10", "lan1000" ]
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
            "subnet": "10.13.37.0/24",
            "pools": [ { "pool": "10.13.37.100 - 10.13.37.200" } ],
            "option-data": [
              { "name": "routers", "data": "10.13.37.1" },
              { "name": "domain-name-servers", "data": "10.13.37.1" }
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
        # so i can overwrite / delete the softlink and change the service live:
        ln -s /etc/kea/kea-dhcp4.conf.tmp /etc/kea/kea-dhcp4.conf || true

        exec kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
      '';

      Restart = "always";
      RestartSec = 10;
      ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
        #!/usr/bin/env bash
        set -euo pipefail

        sleep 1
        REQUIRED_IFACES=(lan2 lan3 lan10 lan1000)
        REQUIRED_IFACES=(lan7)

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

}
