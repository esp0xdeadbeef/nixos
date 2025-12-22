### FILE: ./kea-dhcp6.nix ###
{ pkgs, ... }:
let
  keaConf = "/run/kea-dhcp6.conf";
in
{
  systemd.tmpfiles.rules = [
    "d /run/kea 0755 root root -"
    "d /var/lib/kea 0755 root root -"
  ];

  systemd.services.kea-dhcp6 = {
    description = "Kea DHCPv6 Server (PD pool from /run/kea-dhcp6.conf)";
    wantedBy = [ "multi-user.target" ];

    after = [ "network.target" "v6-pd-generate.service" ];
    wants = [ "v6-pd-generate.service" ];

    serviceConfig = {
      ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -c ${keaConf}";
      Restart = "always";
      RestartSec = 2;
    };
  };
}

