{ lib, pkgs, containerName, pppoeConfig ? { }, ... }:

let
  ifName = "${containerName}-wan";

  cfg = pppoeConfig;

  enabled =
    if cfg ? enable then
      cfg.enable
    else
      false;

  usernameSecret =
    if cfg ? usernameSecret && builtins.isString cfg.usernameSecret then
      cfg.usernameSecret
    else
      throw "pppoe.usernameSecret must be defined";

  passwordSecret =
    if cfg ? passwordSecret && builtins.isString cfg.passwordSecret then
      cfg.passwordSecret
    else
      throw "pppoe.passwordSecret must be defined";

  mtu =
    if cfg ? mtu then
      cfg.mtu
    else
      throw "pppoe.mtu must be defined";

  mru =
    if cfg ? mru then
      cfg.mru
    else
      throw "pppoe.mru must be defined";

  ipv6 =
    if cfg ? ipv6 && builtins.isAttrs cfg.ipv6 then
      cfg.ipv6
    else
      { };

  dhcpv6PD =
    if ipv6 ? dhcpv6PD then
      ipv6.dhcpv6PD
    else
      false;
in
{
  systemd.network.networks =
    {
      "10-${ifName}" = {
        matchConfig.Name = ifName;

        networkConfig =
          {
            IPv4Forwarding = true;
            IPv6Forwarding = true;
            ConfigureWithoutCarrier = true;
          }
          // lib.optionalAttrs (!enabled) {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
          }
          // lib.optionalAttrs enabled {
            DHCP = "no";
            IPv6AcceptRA = false;
          };
      };
    }
    // lib.optionalAttrs enabled {
      "11-ppp0" = {
        matchConfig.Name = "ppp0";

        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = true;
          IPv4Forwarding = true;
          IPv6Forwarding = true;
          DHCP = "no";
          LinkLocalAddressing = "ipv6";
        };
      };
    };

  systemd.services = lib.mkMerge [
    (lib.optionalAttrs enabled {
      pppoe-wan = {
        description = "PPPoE WAN (IPv4 + IPv6)";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        requires = [ "systemd-networkd.service" ];

        path = [
          pkgs.ppp
          pkgs.coreutils
        ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 2;

          ExecStartPre = pkgs.writeShellScript "pppoe-setup" ''
            set -euo pipefail
            umask 077

            mkdir -p /run/ppp/peers

            USERNAME="$(cat /run/secrets/${usernameSecret})"
            PASSWORD="$(cat /run/secrets/${passwordSecret})"

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
            nic-${ifName}

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

            mtu ${toString mtu}
            mru ${toString mru}
            EOF
          '';

          ExecStart = ''
            ${pkgs.ppp}/bin/pppd \
              file /run/ppp/peers/pppoe-wan \
              nodetach \
              debug
          '';
        };
      };
    })

    (lib.optionalAttrs (enabled && dhcpv6PD) {
      dhcpcd-ipv6 = {
        description = "DHCPv6 Prefix Delegation client";
        wantedBy = [ "multi-user.target" ];
        after = [ "pppoe-wan.service" ];
        wants = [ "pppoe-wan.service" ];

        serviceConfig = {
          ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd -6 -d -B -f /etc/dhcpcd.conf ppp0";
          Restart = "always";
          RestartSec = 2;
        };
      };
    })
  ];

  environment.etc = lib.optionalAttrs (enabled && dhcpv6PD) {
    "dhcpcd.conf" = {
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
  };
}
