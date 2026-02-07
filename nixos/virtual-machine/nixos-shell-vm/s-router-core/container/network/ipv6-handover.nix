# ./network/ipv6-handover.nix
{
  outPath,
  pkgs,
  lib,
  ...
}:

let
  topo = import "${outPath}/library/100-fabric-routing/lib/topology.nix";

  transitVid =
    if (topo.transitVlans or [ ]) == [ ] then
      throw "ipv6-handover: topo.transitVlans is empty"
    else
      builtins.elemAt topo.transitVlans 0;

  transitBridge = "br-transit${toString transitVid}";

  coreTransitAddr = "fd42:dead:beef:${toString transitVid}::2/127";
  edgeTransitGw = "fd42:dead:beef:${toString transitVid}::1";

  applyRoute = pkgs.writeShellScript "apply-ipv6-handover-route" ''
    set -euo pipefail

    IF="${transitBridge}"
    GW="${edgeTransitGw}"
    FILE="/run/secrets/subnet-ipv6"

    for i in $(seq 1 80); do
      if ${pkgs.iproute2}/bin/ip link show "$IF" >/dev/null 2>&1; then
        break
      fi
      sleep 0.25
    done

    ${pkgs.iproute2}/bin/ip -6 addr replace ${coreTransitAddr} dev "$IF"

    PREFIX="$(tr -d ' \t\r\n' < "$FILE")"
    ${pkgs.iproute2}/bin/ip -6 route replace "$PREFIX" via "$GW" dev "$IF"
  '';
in
{
  systemd.services.ipv6-handover = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${applyRoute}";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv6.conf.${transitBridge}.accept_ra" = 0;
    "net.ipv6.conf.${transitBridge}.autoconf" = 0;
    "net.ipv6.conf.${transitBridge}.use_tempaddr" = lib.mkForce 0;
    "net.ipv6.conf.${transitBridge}.forwarding" = 1;
  };
}
