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
        exec pppd call pppoe-wan nodetach
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

  ############################################################
  # systemd-networkd: PD from ISP on ppp0 and delegate to lan1010
  ############################################################

  # WAN: request IPv6 + Prefix Delegation from ISP
  #  systemd.network.networks."10-ppp0" = {
  #matchConfig.Name = "ppp0";
  #networkConfig = {
  #  DHCP = "ipv6";
  #IPv6AcceptRA = true; # allow ISP RA if they use it
  #};
  #};
  systemd.network.networks."10-ppp0" = {
    matchConfig.Name = "ppp0";

    networkConfig = {
      DHCP = "ipv6"; # <-- DIT WAS DE MISSENDE SCHAKEL
      IPv6AcceptRA = false; # geen RA nodig
      IPv6Forwarding = true; # nodig voor PD doorgeven
    };

    dhcpV6Config = {
      PrefixDelegationHint = "::/56"; # of /60, afhankelijk van ISP
      UseDelegatedPrefix = true;
    };
  };

}
