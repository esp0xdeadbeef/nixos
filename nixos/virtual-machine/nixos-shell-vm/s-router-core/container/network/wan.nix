{ pkgs, lib, ... }:

{
  ############################################
  # systemd-networkd: manage ppp0
  ############################################
  systemd.network.enable = true;

  systemd.network.networks."10-ppp0" = {
    matchConfig.Name = "ppp0";

    networkConfig = {
      ConfigureWithoutCarrier = true;

      # Accept RA from ISP, learn IPv6 default route
      IPv6AcceptRA = true;

      # Router
      IPv6Forwarding = true;

      DHCP = "no";
      LinkLocalAddressing = "ipv6";
    };
  };

  ############################################
  # PPPoE daemon
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
                  echo "ERROR: missing PPPoE credentials" >&2
                  exit 1
                fi

                cat > /run/ppp/pap-secrets <<EOF
        "$USERNAME" * "$PASSWORD" *
        EOF
                chmod 600 /run/ppp/pap-secrets

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
    description = "DHCPv6 Prefix Delegation client";
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
  # dhcpcd configuration
  ############################################
  environment.etc."dhcpcd.conf" = {
    mode = "0644";
    text = ''
      duid
      persistent

      nohook resolv.conf
      noipv6rs
      noipv4
      ipv6only

      interface ppp0
        iaid 1
        ia_pd 1
    '';
  };

  systemd.services.route-ipv6-pd-to-edge = {
    description = "Route delegated IPv6 prefix to s-router-edge";
    wantedBy = [ "multi-user.target" ];

    after = [
      "systemd-networkd.service"
      "dhcpcd-ipv6.service"
    ];

    requires = [
      "systemd-networkd.service"
      "dhcpcd-ipv6.service"
    ];

    path = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";

      Restart = "on-failure";
      RestartSec = 2;

      ExecStart = pkgs.writeShellScript "route-pd" ''
        set -euo pipefail

        PD="$(${pkgs.iproute2}/bin/ip -6 route show proto dhcp \
          | ${pkgs.gawk}/bin/awk '/unreachable/ { print $2; exit }')"

        # HARD FAIL if PD is missing
        if [ -z "$PD" ]; then
          echo "ERROR: No delegated IPv6 prefix found (proto dhcp unreachable missing)" >&2
          exit 1
        fi

        ${pkgs.iproute2}/bin/ip -6 route replace "$PD" \
          via fd42:dead:beef:100::2 \
          dev br-vlan1010 \
          metric 256
      '';
    };
  };

}
