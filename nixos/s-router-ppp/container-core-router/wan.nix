{ pkgs, lib, ... }:
{
  # PPPoE via pppd (creates ppp0)
  systemd.services.pppoe-pap = {
    description = "ppp connection service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.ppp ];

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "ppp-connect" ''
        set -euo pipefail
        exec pppd call pppoe-wan nodetach debug
      '';
      Restart = "always";
      RestartSec = 2;
    };
  };

  # PPP secrets
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

      noauth
      refuse-chap
      refuse-mschap
      refuse-mschap-v2
      refuse-eap

      defaultroute
      persist

      +ipv6
      ipv6cp-accept-local
      ipv6cp-accept-remote

      mtu 1492
      mru 1492

    '';
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
      ipv6rs
      ia_na 1
      ia_pd 1/::/56
  '';

}
