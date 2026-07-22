{ pkgs, relativeRepo, ... }:
let
  dns = import (relativeRepo.module "prod-network/current/dns-runtime-addresses.nix");
  ip = "${pkgs.iproute2}/bin/ip";
in
{
  # TEMPORARY NETWORK-* COMPATIBILITY OVERRIDE.
  #
  # The renderer currently copies the core service-link routes into every
  # tenant policy table. Equal-prefix routes then let VLAN 2 or VLAN 7 DNS
  # traffic leave through another tenant's upstream interface. Remove those
  # copied routes so each table's existing, lane-specific default is used.
  #
  # Remove this entire file, its import, warning, and parity assertion once the
  # network-* service-route closure emits the core DNS endpoint only through
  # the requester's relation-bound upstream lane.
  containers.policy.config = {
    systemd.services.s-router-prod-core-dns-path-reconcile = {
      description = "Reconcile production core DNS policy routes";
      after = [ "systemd-networkd.service" ];
      requires = [ "systemd-networkd.service" ];

      serviceConfig.Type = "oneshot";

      script = ''
        set -euo pipefail

        remove_all() {
          family=$1
          table=$2
          prefix=$3

          while ${ip} "$family" route del table "$table" "$prefix" 2>/dev/null; do
            :
          done
        }

        route_uses_lane() {
          family=$1
          destination=$2
          source=$3
          incoming=$4
          table=$5
          outgoing=$6

          route="$(${ip} "$family" route get "$destination" from "$source" iif "$incoming")"
          ${pkgs.gnugrep}/bin/grep -Fq "dev $outgoing table $table" <<<"$route"
        }

        for table in 1004 1006; do
          remove_all -4 "$table" "${dns.resolver.ipv4}/32"
          remove_all -4 "$table" "${dns.resolver.ipv4}/31"
          remove_all -6 "$table" "${dns.resolver.ipv6}/128"
          remove_all -6 "$table" "${dns.resolver.ipv6}/127"
        done

        route_uses_lane -4 "${dns.resolver.ipv4}" \
          "${dns.requesters.access-vlan2.ipv4}" down-vlan2 1004 upstream-vlan2
        route_uses_lane -6 "${dns.resolver.ipv6}" \
          "${dns.requesters.access-vlan2.ipv6}" down-vlan2 1004 upstream-vlan2
        route_uses_lane -4 "${dns.resolver.ipv4}" \
          "${dns.requesters.access-vlan7.ipv4}" downstr-vlan7 1006 upstream-vlan7
        route_uses_lane -6 "${dns.resolver.ipv6}" \
          "${dns.requesters.access-vlan7.ipv6}" downstr-vlan7 1006 upstream-vlan7
      '';
    };

    systemd.timers.s-router-prod-core-dns-path-reconcile = {
      description = "Reconcile production core DNS policy routes after link changes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1s";
        OnUnitActiveSec = "5s";
        Unit = "s-router-prod-core-dns-path-reconcile.service";
      };
    };
  };
}
