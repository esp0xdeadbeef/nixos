{ pkgs, lib, ... }:
{

  environment.etc."kea/kea-dhcp6.conf".text = ''
    {
      "Dhcp6": {
        "interfaces-config": {
          "interfaces": [ "lan1010" ]
        },

        "preferred-lifetime": 3600,
        "valid-lifetime": 7200,

        "lease-database": {
          "type": "memfile",
          "persist": true,
          "name": "/var/lib/kea/dhcp6.leases"
        },

        "subnet6": [
          {
            "subnet": "::/0",

            "pd-pools": [
              {
                "prefix": "2001:4860:4860::",
                "prefix-len": 56,
                "delegated-len": 64
              }
            ]
          }
        ]
      }
    }
  '';

  systemd.services.kea-dhcp6 = {
    description = "Kea DHCPv6 Server (PD)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -c /etc/kea/kea-dhcp6.conf";
      Restart = "always";
      RestartSec = 5;
    };
  };

}
