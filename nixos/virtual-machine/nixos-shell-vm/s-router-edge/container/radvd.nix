{
  config,
  lib,
  pkgs,
  ...
}:

let
  prefixFile = "/run/secrets/subnet-ipv6";

  # Explicit, declarative: only these get a /64 + RA
  lanIfaces = [
    "lan7"
    "lan10"
    "lan20"
  ];

  genScript = pkgs.writeShellScript "v6-ra-generate" ''
        set -euo pipefail

        PREFIX_FILE="${prefixFile}"
        RADVD_CONF="/run/radvd.conf"
        ALLOWED_IFACES="${lib.concatStringsSep " " lanIfaces}"

        if [ ! -r "$PREFIX_FILE" ]; then
          echo "ERROR: missing prefix file $PREFIX_FILE" >&2
          exit 1
        fi

        RAW_PREFIX="$(tr -d ' \t\n' < "$PREFIX_FILE")"
        PREFIX_LEN="''${RAW_PREFIX##*/}"
        BASE_PREFIX="''${RAW_PREFIX%%/*}"

        if [ "$PREFIX_LEN" != "48" ]; then
          echo "ERROR: expected /48, got /$PREFIX_LEN" >&2
          exit 1
        fi

        EXPANDED="$(sipcalc "$BASE_PREFIX" | awk '/Expanded Address/ {print $NF}')"
        IFS=':' read -r H1 H2 H3 _ <<< "$EXPANDED"

        echo "[v6-ra] base prefix: $H1:$H2:$H3::/48"

        > "$RADVD_CONF"

        for IFACE in $ALLOWED_IFACES; do
          if [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[v6-ra] skipping $IFACE (not present)"
            continue
          fi

          # must be UP
          ip link show "$IFACE" | grep -q "UP" || {
            echo "[v6-ra] skipping $IFACE (not UP)"
            continue
          }

          # numeric suffix (lan7 -> 7)
          IDX="$(echo "$IFACE" | sed -n 's/[^0-9]*\([0-9]\+\)$/\1/p')"
          if [ -z "$IDX" ]; then
            echo "[v6-ra] skipping $IFACE (no numeric suffix)"
            continue
          fi

          HEX="$(printf "%04x" "$IDX")"
          PREFIX="$H1:$H2:$H3:$HEX"

          echo "[v6-ra] $IFACE -> $PREFIX::/64"

          ip -6 addr replace "$PREFIX::1/64" dev "$IFACE"
          ip -6 route replace "$PREFIX::/64" dev "$IFACE" proto static metric 256

          cat >> "$RADVD_CONF" <<EOF
    interface $IFACE {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;

      AdvManagedFlag off;
      AdvOtherConfigFlag off;

      prefix $PREFIX::/64 {
        AdvOnLink on;
        AdvAutonomous on;
      };
    };
    EOF
        done

        if ! grep -q '^interface ' "$RADVD_CONF"; then
          echo "ERROR: generated empty $RADVD_CONF (no eligible interfaces?)" >&2
          exit 1
        fi

        echo "[v6-ra] wrote $RADVD_CONF"
  '';
in
{
  # Router behavior (you likely already have this elsewhere)
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 1;

  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
    pkgs.sipcalc
  ];

  systemd.services.radvd-generate-configs = {
    description = "Generate radvd.conf + assign deterministic /64s from /48";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    # Critical: provide PATH for the script
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.sipcalc
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = genScript;
      RemainAfterExit = true;
    };
  };

  systemd.services.radvd = {
    description = "Router Advertisement Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "radvd-generate-configs.service" ];
    requires = [ "radvd-generate-configs.service" ];

    # Optional, but nice if you ever add ExecStartPre/Post helpers
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.iproute2
      pkgs.radvd
    ];

    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /run/radvd.conf";
      Restart = "always";
      RestartSec = "2s";
    };
  };
}
