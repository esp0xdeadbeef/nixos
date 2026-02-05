{
  config,
  pkgs,
  lib,
  args,
  ...
}:

let
  keaPkg = pkgs.kea;

  # LANs that run DHCPv4
  lans = lib.filter (l: l.dhcp4 or false) args.lans;

  svcFor = l: "kea-dhcp4-${l.name}";

  #
  # PRE: wait until interface exists and is UP + LOWER_UP
  #
  waitIface = pkgs.writeShellScript "wait-iface-ready" ''
    set -euo pipefail
    IF="$1"

    echo "[kea] waiting for interface $IF"

    for i in $(seq 1 80); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        if ${pkgs.iproute2}/bin/ip link show "$IF" | \
           ${pkgs.gnugrep}/bin/grep -q "UP.*LOWER_UP"; then
          echo "[kea] interface $IF is UP + LOWER_UP"
          exit 0
        fi
      fi
      sleep 0.25
    done

    echo "[kea] ERROR: interface $IF never became RUNNING" >&2
    ${pkgs.iproute2}/bin/ip link show "$IF" || true
    exit 1
  '';

  #
  # POST: verify Kea actually bound UDP/67 on the interface
  #
  postCheck = pkgs.writeShellScript "kea-post-check" ''
    set -euo pipefail
    IF="$1"

    echo "[kea] post-check: verifying DHCP socket on $IF"
    sleep 0.5

    IPS="$(${pkgs.iproute2}/bin/ip -4 addr show "$IF" | \
           ${pkgs.gawk}/bin/awk '/inet / {print $2}' | cut -d/ -f1)"

    FOUND=0
    for IP in $IPS; do
      if ${pkgs.iproute2}/bin/ss -u -l -n | \
         ${pkgs.gnugrep}/bin/grep -q "$IP:67"; then
        FOUND=1
        break
      fi
    done

    if [ "$FOUND" -ne 1 ]; then
      echo "[kea] ERROR: Kea is not listening on UDP/67 for $IF" >&2
      echo "[kea] interface IPs: $IPS" >&2
      ${pkgs.iproute2}/bin/ss -u -l -n >&2
      exit 1
    fi

    echo "[kea] OK: Kea bound to UDP/67 on $IF"
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
          pkgs.gawk
        ];

        serviceConfig = {
          Type = "simple";

          # PRE: interface truth
          ExecStartPre = [
            "${waitIface} ${lib.escapeShellArg l.iface}"
          ];

          # MAIN
          ExecStart = "${keaPkg}/bin/kea-dhcp4 -d -c /run/etc/kea/${l.name}.json";

          # POST: socket truth
          ExecStartPost = [
            "${postCheck} ${lib.escapeShellArg l.iface}"
          ];

          Restart = "always";
          RestartSec = "2s";

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
    }) lans
  );
}
