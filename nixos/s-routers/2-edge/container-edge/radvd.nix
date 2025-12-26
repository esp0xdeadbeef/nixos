{ pkgs, lib, ... }:

let
  wanIf = "lan1010";

  lanMap = {
    lan7 = 7;
    lan10 = 10;
    lan20 = 20;
  };

  gen = pkgs.writeShellScript "v6-ra-generate" ''
        set -euo pipefail

        WAN="${wanIf}"
        RADVD="/run/radvd.conf"

        echo "[v6-ra-generate] Reading routed prefix from RA on $WAN"

        RA_PREFIX="$(
          ${pkgs.iproute2}/bin/ip -6 route show dev "$WAN" proto ra \
            | ${pkgs.gawk}/bin/awk '
                /via/ && $1 ~ /\/[0-9]+$/ {
                  split($1, a, "/");
                  if (a[2] <= 64) print $1
                }' \
            | ${pkgs.coreutils}/bin/sort -t/ -k2,2n \
            | ${pkgs.coreutils}/bin/head -n1
        )"

        if [ -z "''${RA_PREFIX:-}" ]; then
          echo "[v6-ra-generate] No RA routed prefix found yet; leaving existing $RADVD in place"
          exit 0
        fi

        BASE="$(echo "$RA_PREFIX" | ${pkgs.coreutils}/bin/cut -d/ -f1)"
        LEN="$(echo "$RA_PREFIX" | ${pkgs.coreutils}/bin/cut -d/ -f2)"

        if [ "$LEN" -gt 64 ]; then
          echo "ERROR: Routed prefix length $LEN > 64; cannot carve /64s" >&2
          exit 1
        fi

        echo "[v6-ra-generate] Upstream prefix: $BASE/$LEN"

        tmp="$(${pkgs.coreutils}/bin/mktemp)"
        : > "$tmp"

        for entry in ${
          lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "${n}:${toString v}") lanMap)
        }; do
          IFACE="''${entry%%:*}"
          IDX="''${entry##*:}"

          if [ ! -d "/sys/class/net/$IFACE" ]; then
            echo "[v6-ra-generate] skipping $IFACE (not present)"
            continue
          fi

          PREFIX="''${BASE%::}:$IDX::"
          echo "[v6-ra-generate] $IFACE → $PREFIX/64"

          # Stable router address on each LAN
          ${pkgs.iproute2}/bin/ip -6 addr replace "$PREFIX""1/64" dev "$IFACE"

          # On-link route for that /64 (defensive)
          ${pkgs.iproute2}/bin/ip -6 route replace "$PREFIX/64" dev "$IFACE" proto static metric 256

          cat >> "$tmp" <<EOF
    interface $IFACE {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;

      AdvDefaultLifetime 1800;
      AdvManagedFlag off;
      AdvOtherConfigFlag off;

      prefix $PREFIX/64 {
        AdvOnLink on;
        AdvAutonomous on;
      };
    };
    EOF
        done

        if [ ! -s "$tmp" ]; then
          echo "[v6-ra-generate] No LAN interfaces present from lanMap; not updating $RADVD"
          rm -f "$tmp"
          exit 0
        fi

        install -m 0644 "$tmp" "$RADVD"
        rm -f "$tmp"

        echo "[v6-ra-generate] Wrote $RADVD"

        # Signal to ExecStartPost that config was updated
        touch /run/v6-ra-generate.updated
  '';
in
{
  services.networkd-dispatcher.enable = true;

  environment.etc."networkd-dispatcher/routable.d/50-v6-ra-generate".source =
    pkgs.writeShellScript "v6-ra-dispatch" ''
      #!/bin/sh
      exec ${pkgs.systemd}/bin/systemctl start v6-ra-generate.service
    '';

  systemd.services.v6-ra-generate = {
    path = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
      pkgs.findutils
    ];

    serviceConfig = {
      Type = "oneshot";
      wantedBy = [ "multi-user.target" ];
      ExecStart = gen;
      Restart = "no";

      # Restart radvd only if we actually updated the config this run
      ExecStartPost = [
        "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/test -f /run/v6-ra-generate.updated && ${pkgs.coreutils}/bin/rm -f /run/v6-ra-generate.updated && ${pkgs.systemd}/bin/systemctl restart radvd.service || true'"
      ];

    };
  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /run/radvd.conf";
      Restart = "always";
    };
  };
}
