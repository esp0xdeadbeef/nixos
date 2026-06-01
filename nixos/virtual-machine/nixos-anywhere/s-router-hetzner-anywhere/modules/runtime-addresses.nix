{ lib
, pkgsForRenderer
, nebulaRuntime
, runtimeFacts
,
}:
let
  inherit (nebulaRuntime) internalWan;
  inherit (runtimeFacts)
    lighthousePublicIPv4SecretPath
    primaryInterfaceFallback
    primaryInterfaceMac
    publicIPv4Gateway
    publicIPv4SecretPath
    publicIPv6AddressSecretPath
    publicIPv6SecretPath
    routedIPv6PrefixesSecretPath
    ;
in
{
  systemd.services.hetzner-runtime-addresses = {
    description = "Apply Hetzner runtime public addresses from root-only runtime files";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    wants = [ "systemd-networkd.service" ];
    path = with pkgsForRenderer; [
      coreutils
      gnugrep
      iproute2
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      primary_if=""
      for candidate in /sys/class/net/*; do
        [ -e "$candidate/address" ] || continue
        if [ "$(tr '[:upper:]' '[:lower:]' < "$candidate/address")" = "${lib.toLower primaryInterfaceMac}" ]; then
          primary_if="''${candidate##*/}"
          break
        fi
      done
      if [ -z "$primary_if" ] && [ -e "/sys/class/net/${primaryInterfaceFallback}" ]; then
        primary_if="${primaryInterfaceFallback}"
      fi
      if [ -z "$primary_if" ]; then
        echo "could not find Hetzner primary interface with MAC ${primaryInterfaceMac}" >&2
        exit 1
      fi
      ip link set dev "$primary_if" up
      ip link set dev br-wan up
      br_wan_ready=0
      for _ in $(seq 1 20); do
        if networkctl status br-wan --no-pager 2>/dev/null | grep -Eq 'State: (configured|routable|degraded)'; then
          br_wan_ready=1
          break
        fi
        sleep 1
      done
      if [ "$br_wan_ready" -ne 1 ]; then
        echo "br-wan did not reach configured state before applying Hetzner runtime routes" >&2
        networkctl status br-wan --no-pager >&2 || true
        exit 1
      fi

      public4="$(tr -d '\n' < ${publicIPv4SecretPath})"
      public6_prefix="$(tr -d '\n' < ${publicIPv6SecretPath})"
      public6_addr="$(tr -d '\n' < ${publicIPv6AddressSecretPath})"

      ip address replace "$public4/32" dev "$primary_if"
      ip address replace "$public6_addr" dev "$primary_if"

      if [ -s ${lighthousePublicIPv4SecretPath} ]; then
        lighthouse4="$(tr -d '\n' < ${lighthousePublicIPv4SecretPath})"
        ip address replace "$lighthouse4/32" dev "$primary_if"
      fi

      if [ -s ${routedIPv6PrefixesSecretPath} ]; then
        while IFS= read -r prefix; do
          [ -n "$prefix" ] || continue
          [ "$prefix" = "$public6_prefix" ] && continue
          case "$prefix" in
            *::/64)
              ip address replace "''${prefix%::/64}::1/128" dev "$primary_if"
              ip -6 route replace "$prefix" via ${internalWan.coreAddress6Bare} dev br-wan onlink
              ;;
          esac
        done < ${routedIPv6PrefixesSecretPath}
      fi

      ip route replace ${publicIPv4Gateway}/32 dev "$primary_if" scope link
      ip route replace default via ${publicIPv4Gateway} dev "$primary_if"
      ip -6 route replace default via fe80::1 dev "$primary_if"
    '';
  };
}
