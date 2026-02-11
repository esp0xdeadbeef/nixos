{ pkgs, lib, ... }:

let
  iface = "br-vlan1010";

  # Wait until interface exists and is usable
  waitIface = pkgs.writeShellScript "wait-iface-ready" ''
    set -euo pipefail
    IF="$1"

    # ~10s max
    for i in $(seq 1 40); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "UP"; then
          if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "LOWER_UP"; then
            exit 0
          fi
          # allow after some tries if carrier flag is missing
          if [ "$i" -ge 12 ]; then
            exit 0
          fi
        fi
      fi
      sleep 0.25
    done

    echo "iface $IF not ready after timeout" >&2
    exit 1
  '';

  # Prove Kea is actually listening on the right interface
  postCheck = pkgs.writeShellScript "kea-post-check" ''
    set -euo pipefail
    IF="$1"

    # give kea a moment to bind
    sleep 0.5

    if ! ${pkgs.iproute2}/bin/ss -ulpn | \
         ${pkgs.gnugrep}/bin/grep -q "10.255.255.*kea-dhcp4" ; then
      echo "Kea is NOT listening on $IF" >&2
      echo "Current UDP listeners:" >&2
      ${pkgs.iproute2}/bin/ss -ulpn >&2
      exit 1
    fi

  '';
in
{
  ############################################
  # Kea config
  ############################################
  environment.etc."kea/vlan1010.json".text = builtins.toJSON {
    Dhcp4 = {
      "interfaces-config" = {
        interfaces = [ iface ];
      };

      "lease-database" = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/vlan1010.leases";
      };

      subnet4 = [
        {
          id = 1010;
          subnet = "10.255.255.0/29";

          pools = [
            { pool = "10.255.255.4-10.255.255.6"; }
          ];

          option-data = [
            {
              name = "routers";
              data = "10.255.255.1";
            }
          ];
        }
      ];
    };
  };

  ############################################
  # Kea systemd unit (real correctness)
  ############################################
  systemd.services.kea-dhcp4 = {
    description = "Kea DHCPv4 (Transit ${iface})";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];

    path = [
      pkgs.iproute2
      pkgs.gnugrep
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "simple";

      # PRE: guarantee iface exists
      ExecStartPre = [
        "${waitIface} ${iface}"
      ];

      # REAL service
      ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -d -c /etc/kea/vlan1010.json";

      # POST: prove kernel socket truth
      ExecStartPost = [
        "${postCheck} ${iface}"
      ];

      Restart = "always";
      RestartSec = 2;

      RuntimeDirectory = "kea";
      StateDirectory = "kea";

      CapabilityBoundingSet = [
        "CAP_NET_BIND_SERVICE"
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
      AmbientCapabilities = [
        "CAP_NET_BIND_SERVICE"
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };
  };
}
