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
