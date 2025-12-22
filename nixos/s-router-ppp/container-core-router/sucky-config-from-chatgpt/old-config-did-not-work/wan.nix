### FILE: ./wan.nix ###
{ pkgs, lib, ... }:
{
  systemd.services.pppoe-pap = {
    description = "PPPoE connection service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.ppp pkgs.iproute2 ];

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "ppp-connect" ''
        set -euo pipefail
        exec pppd call pppoe-wan nodetach debug
      '';
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

  # Workaround: ensure we always have an IPv6 default route via ppp0 (point-to-point).
  # pppd doesn't consistently manage an IPv6 default route like it does for IPv4. :contentReference[oaicite:2]{index=2}
  environment.etc."ppp/ip-up.d/20-ipv6-default-route" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # pppd sets $PPP_IFACE
      IFACE="$PPP_IFACE"
      [ -z "$IFACE" ] && IFACE="ppp0"

      # Only touch IPv6 when the iface is actually up
      ip link show dev "$IFACE" >/dev/null 2>&1 || exit 0

      # Default via point-to-point device is valid
      ip -6 route replace default dev "$IFACE" metric 512 || true
    '';
  };

  # DHCPv6-PD via systemd-networkd on PPP
  systemd.network.networks."10-ppp0-ipv6" = {
    matchConfig.Name = "ppp0";

    networkConfig = {
      DHCP = "ipv6";
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      DHCPPrefixDelegation = true;
    };

    # Important on links where no RA is present; DHCPv6 client should run anyway. :contentReference[oaicite:3]{index=3}
    dhcpV6Config = {
      WithoutRA = "solicit";
      UseDNS = false;

      # NixOS/networkd examples commonly use a hint like ::/48 for PD. :contentReference[oaicite:4]{index=4}
      PrefixDelegationHint = "::/48";
    };
  };
}

