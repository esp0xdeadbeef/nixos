{ pkgs, lib, ... }:

let
  gen = pkgs.writeShellScript "v6-pd-generate" ''
        set -euo pipefail
        set -x

        echo "[v6-pd-generate] Determining delegated prefix from ISP"

        # Find delegated prefix (proto dhcp installs it as unreachable)
        PD_PREFIX="$(${pkgs.iproute2}/bin/ip -6 route show proto dhcp \
          | ${pkgs.gawk}/bin/awk '/unreachable/ { print $2; exit }')"

        if [ -z "''${PD_PREFIX:-}" ]; then
          echo "ERROR: Could not determine delegated prefix from ISP" >&2
          exit 1
        fi

        PD_BASE="$(printf '%s' "$PD_PREFIX" | ${pkgs.gawk}/bin/awk -F/ '{print $1}')"
        PD_LEN="$(printf '%s' "$PD_PREFIX" | ${pkgs.gawk}/bin/awk -F/ '{print $2}')"

        if [ -z "''${PD_BASE:-}" ] || [ -z "''${PD_LEN:-}" ]; then
          echo "ERROR: Failed to parse PD_PREFIX=$PD_PREFIX" >&2
          exit 1
        fi

        echo "[v6-pd-generate] ISP delegated prefix: $PD_BASE/$PD_LEN"

        # Pick ONE /64 out of the PD for the transit LAN (router<->OPNsense).
        # For a /48 this becomes: 2a10:...:1::/64
        # Deterministic and does NOT depend on RA already working.
        if [ "$PD_LEN" -lt 64 ]; then
          LAN_PREFIX="''${PD_BASE%::}:1::"
        elif [ "$PD_LEN" -eq 64 ]; then
          LAN_PREFIX="$PD_BASE"
        else
          echo "ERROR: PD prefix length $PD_LEN is > 64; cannot carve a /64 sanely here" >&2
          exit 1
        fi

        echo "[v6-pd-generate] Router transit LAN prefix: $LAN_PREFIX/64"

        # Ensure router has a stable on-link route for the transit /64 on lan1010.
        # (Address assignment itself should be handled by your network config; this only ensures routing.)
        ${pkgs.iproute2}/bin/ip -6 route replace "$LAN_PREFIX/64" dev lan1010 proto static metric 256

        mkdir -p /run/kea

        # --- Kea DHCPv6 PD ONLY configuration ---
        # Note: Kea config is JSON. Do NOT put /* comments */ in production configs.
        cat > /run/kea/kea-dhcp6.conf <<EOF
    {
      "Dhcp6": {
        "interfaces-config": {
          "interfaces": [ "lan1010" ]
        },

        "lease-database": {
          "type": "memfile",
          "persist": false
        },

        "preferred-lifetime": 3600,
        "valid-lifetime": 7200,

        "subnet6": [
          {
            "id": 1,
            "interface": "lan1010",
            "subnet": "$LAN_PREFIX/64",

            "pd-pools": [
              {
                "prefix": "$PD_BASE",
                "prefix-len": $PD_LEN,
                "delegated-len": 56
              }
            ]
          }
        ]
      }
    }
    EOF

        # --- Router Advertisement on lan1010 ---
        # CRITICAL: AdvDefaultLifetime != 0 so OPNsense installs ::/0 via this router.
        cat > /run/radvd.conf <<EOF
    interface br-vlan1010 {
      AdvSendAdvert on;
      MinRtrAdvInterval 10;
      MaxRtrAdvInterval 30;

      # Make us the default router for downstream (this is what gives ::/0)
      AdvDefaultLifetime 1800;

      # We are NOT doing DHCPv6 addresses (IA_NA), only PD.
      # "OtherConfigFlag" can be on if you want to hand out DNS via DHCPv6 later.
      AdvManagedFlag off;
      AdvOtherConfigFlag on;

      prefix $LAN_PREFIX/64 {
        AdvOnLink on;
        AdvAutonomous on;
      };
    };
    EOF

        echo "[v6-pd-generate] Wrote /run/kea/kea-dhcp6.conf and /run/radvd.conf"
        echo "sleep infinity:"
        sleep infinity
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /run/kea 0755 root root -"
    "d /var/lib/kea 0755 root root -"
  ];

  systemd.services.v6-pd-generate = {
    path = [
      pkgs.iproute2
      pkgs.gawk
      pkgs.coreutils
    ];

    serviceConfig = {
      ExecStart = gen;
      Restart = "always";
      ExecStartPost = [
        "${pkgs.systemd}/bin/systemctl restart kea-dhcp6.service"
        "${pkgs.systemd}/bin/systemctl restart radvd.service"
      ];
    };
  };

  systemd.services.radvd = {
    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /run/radvd.conf";
      Restart = "always";
    };
  };

  systemd.services.kea-dhcp6 = {
    serviceConfig = {
      ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -c /run/kea/kea-dhcp6.conf";
      Restart = "always";
    };
  };
}
