{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  mkBridge = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix" {
    inherit lib pkgs;
  };

  pppTable = 100;
  pppRulePrio = 100;
in
{
  ############################
  # WAN trunk (ISP VLAN 6)
  ############################
  systemd.network.networks."10-wan-trunk" = {
    matchConfig.Name = "wan";
    networkConfig = {
      DHCP = "no";
      VLAN = [ "wan.6" ];
    };
  };

  # Build wan.6 + br-wan6
  imports = [
    (mkBridge "wan" 6 { bridge = "br-wan6"; })
  ];

  ############################
  # networkd: ppp0 handling
  ############################
  systemd.network.networks."10-ppp0" = {
    matchConfig.Name = "ppp0";

    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";

      IPv6AcceptRA = true;
      IPv6Forwarding = true;
      IPv4Forwarding = true;
      LinkLocalAddressing = "ipv6";
    };

    ipv6AcceptRAConfig = {
      UseDNS = false;
      DHCPv6Client = "no";
    };
  };

  ############################
  # PPPoE service
  ############################
  systemd.services.pppoe-wan = {
    description = "PPPoE WAN (Freedom Internet, IPv4 + IPv6)";
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

      ExecStartPre = pkgs.writeShellScript "ppp-setup" ''
                set -euo pipefail
                umask 077

                mkdir -p /run/ppp/peers

                USERNAME="$(cat /run/secrets/pppoe-username)"
                PASSWORD="$(cat /run/secrets/pppoe-password)"

                # PAP / CHAP secrets (runtime only)
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

        # IMPORTANT:
        # We do NOT let pppd install default routes.
        # Policy routing is installed by our oneshot unit below.
        nodefaultroute
        persist

        +ipv6
        ipv6cp-accept-local
        ipv6cp-accept-remote

        mtu 1500
        mru 1500
        EOF
      '';

      ExecStart = "${pkgs.ppp}/bin/pppd file /run/ppp/peers/pppoe-wan nodetach";
    };
  };

  ############################
  # Policy routing (portable)
  #
  # Forces all internet-bound traffic to use table 100,
  # whose default route is dev ppp0.
  ############################
  systemd.services.ppp0-policy-routing = {
    description = "Install PPPoE policy routing (table ${toString pppTable})";
    wantedBy = [ "multi-user.target" ];

    # Order: pppd up first, then we program rules.
    after = [
      "pppoe-wan.service"
      "systemd-networkd.service"
    ];
    requires = [ "pppoe-wan.service" ];

    path = [
      pkgs.iproute2
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "ppp0-policy-routing" ''
        set -euo pipefail

        # Wait for ppp0 to exist
        for i in $(seq 1 120); do
          ip link show ppp0 >/dev/null 2>&1 && break
          sleep 0.25
        done
        ip link show ppp0 >/dev/null 2>&1 || {
          echo "ppp0 did not appear" >&2
          exit 1
        }

        # Make sure table exists (no-op if it does)
        # (rt_tables name is optional; route by table number works regardless)
        mkdir -p /etc/iproute2
        touch /etc/iproute2/rt_tables
        grep -qE '^\s*${toString pppTable}\s+pppoe\s*$' /etc/iproute2/rt_tables || \
          echo '${toString pppTable} pppoe' >> /etc/iproute2/rt_tables

        # 1) Install default route in table 100 via ppp0
        # For point-to-point ppp0: "default dev ppp0" is correct.
        ip route replace default dev ppp0 table ${toString pppTable}

        # 2) Install policy rule: prefer table 100 for all destinations
        # Use "replace" pattern: delete then add to ensure idempotence.
        while ip rule del pref ${toString pppRulePrio} >/dev/null 2>&1; do :; done
        ip rule add pref ${toString pppRulePrio} to 0.0.0.0/0 lookup ${toString pppTable}

        # 3) Ensure normal local routing still works
        # (Kernel keeps local/main/default rules; we don't touch them.)

        # Debug print (shows in journal)
        ip rule show
        ip route show table ${toString pppTable}
      '';
    };
  };
}
