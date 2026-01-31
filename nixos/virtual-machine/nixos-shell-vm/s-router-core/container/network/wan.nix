{ pkgs, lib, ... }:

{
  ############################################
  # systemd-networkd: manage ppp0
  ############################################
  systemd.network.enable = true;

  systemd.network.networks."10-ppp0" = {
    matchConfig = {
      Name = "ppp0";
    };

    networkConfig = {
      ConfigureWithoutCarrier = true;

      # Accept RA from ISP, learn IPv6 default route
      IPv6AcceptRA = true;

      # This container is a router
      IPv6Forwarding = true;

      DHCP = "no";
      LinkLocalAddressing = "ipv6";
    };
  };

  ############################################
  # PPPoE daemon (runtime-generated config)
  ############################################
  systemd.services.pppoe-pap = {
    description = "PPPoE WAN (IPv4 + IPv6)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.ppp
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "simple";

      ExecStartPre = pkgs.writeShellScript "ppp-setup" ''
                set -euo pipefail
                umask 077

                mkdir -p /run/ppp/peers

                USERNAME="$(cat /run/secrets/pppoe-username)"
                PASSWORD="$(cat /run/secrets/pppoe-password)"

                if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
                  echo "ERROR: missing PPPoE credentials in /run/secrets" >&2
                  exit 1
                fi

                # pap-secrets is NOT a shell script
                cat > /run/ppp/pap-secrets <<EOF
        "$USERNAME" * "$PASSWORD" *
        EOF
                chmod 600 /run/ppp/pap-secrets

                # Run PPPoE on the interface that actually sees the AC
                # You verified this with: pppoe-discovery -I br-wan6
                cat > /run/ppp/peers/pppoe-wan <<EOF
        plugin pppoe.so
        nic-br-wan6

        user "$USERNAME"
        password "$PASSWORD"

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
        EOF
      '';

      ExecStart = ''
        ${pkgs.ppp}/bin/pppd \
          file /run/ppp/peers/pppoe-wan \
          nodetach \
          debug
      '';

      Restart = "always";
      RestartSec = 2;
    };
  };

  ############################################
  # DHCPv6-PD client
  ############################################
  systemd.services.dhcpcd-ipv6 = {
    description = "DHCPv6-PD client";
    wantedBy = [ "multi-user.target" ];
    after = [ "pppoe-pap.service" ];
    wants = [ "pppoe-pap.service" ];

    serviceConfig = {
      ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -d -B -f /etc/dhcpcd.conf ppp0";
      Restart = "always";
      RestartSec = 2;
    };
  };

  ############################################
  # dhcpcd config
  ############################################
  environment.etc."dhcpcd.conf" = {
    mode = "0644";
    text = ''
      duid
      persistent

      # Prevent dhcpcd touching resolv.conf
      nohook resolv.conf

      # Only PD, RA is handled by networkd
      noipv6rs
      noipv4
      ipv6only

      interface ppp0
        iaid 1
        ia_pd 1 br-vlan1010/0/64
    '';
  };
}
