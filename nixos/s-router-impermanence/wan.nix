{ pkgs, lib, ... }:
{


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
}
