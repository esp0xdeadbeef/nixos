{ pkgs, lib, ... }:
{
  systemd.network.enable = true;

  # ppp0 is created by pppd; networkd can still manage it after it appears.
  systemd.network.networks."10-ppp0" = {
    matchConfig.Name = "ppp0";

    networkConfig = {
      ConfigureWithoutCarrier = true;

      IPv6AcceptRA = true;

      IPv6Forwarding = true;
      DHCP = "no";
      LinkLocalAddressing = "ipv6";
    };

    # Ask for a delegated prefix. /56 is common; adjust if your ISP only gives /64.
    # This is standard networkd behavior. :contentReference[oaicite:2]{index=2}
    dhcpV6Config = {
      PrefixDelegationHint = "::/56";
      UseDNS = false;
      UseNTP = false;
      UseHostname = false;
    };

    # If your upstream is weird about signalling DHCPv6 in RA, forcing the DHCPv6 client can matter. :contentReference[oaicite:3]{index=3}
    ipv6AcceptRAConfig = {
      UseDNS = false;
      DHCPv6Client = "always";
    };
  };

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
        defaultroute
        persist
        +ipv6
        ipv6cp-accept-local
        ipv6cp-accept-remote
        mtu 1492
        mru 1492
        EOF
      '';

      ExecStart = "${pkgs.ppp}/bin/pppd file /run/ppp/peers/pppoe-wan nodetach";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
