{
  pkgs,
  lib,
  args,
}:
{ ... }:

let
  lans = lib.filter (l: l.dhcp4 or false) args.lans;

  svcFor = l: "kea-dhcp4-${l.name}";

  # Wait until iface is actually usable for raw sockets (veth peer attached).
  waitIface = pkgs.writeShellScript "wait-iface-ready" ''
    set -euo pipefail
    IF="$1"


    # max ~10s
    for i in $(seq 1 40); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        # require UP
        if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "UP"; then
          # prefer LOWER_UP (carrier/peer)
          if ${pkgs.iproute2}/bin/ip link show "$IF" | ${pkgs.gnugrep}/bin/grep -q "LOWER_UP"; then
            exit 0
          fi
          # allow after some tries once it's UP
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

in
{
  systemd.services = lib.listToAttrs (
    map (l: {
      name = svcFor l;
      value = {
        description = "Kea DHCPv4 on ${l.iface}";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-networkd.service" ];
        requires = [ "systemd-networkd.service" ];

        path = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.gnugrep
        ];

        serviceConfig = {
          Type = "simple";

          ExecStartPre = [ "${waitIface} ${lib.escapeShellArg l.iface}" ];

          ExecStart = "${pkgs.kea}/bin/kea-dhcp4 -d -c /etc/kea/${l.name}.json";

          RuntimeDirectory = "kea";
          RuntimeDirectoryMode = "0755";
          StateDirectory = "kea";
          StateDirectoryMode = "0755";

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

          Restart = "always";
          RestartSec = "2s";
        };
      };
    }) lans
  );
}
