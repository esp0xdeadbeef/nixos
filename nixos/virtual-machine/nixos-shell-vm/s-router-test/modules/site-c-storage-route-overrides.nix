{
  lib,
  pkgs,
  siteCStorageOverlay ? null,
  baseContainer ? null,
}:
let
  overlay =
    if builtins.isAttrs siteCStorageOverlay then siteCStorageOverlay else null;

  baseConfigModule =
    if
      builtins.isAttrs baseContainer
      && baseContainer ? config
      && builtins.isFunction baseContainer.config
    then
      baseContainer.config
    else
      null;

  endpoint4 =
    if overlay != null then
      overlay.nodes."nas-node01".lighthouse.endpoint
    else
      null;

  endpoint6 =
    if overlay != null then
      overlay.nodes."nas-node01".lighthouse.endpoint6
    else
      null;
in
lib.optionalAttrs (overlay != null) {
  c-router-policy = {
    config =
      {
        lib,
        pkgs,
        ...
      }@args:
      let
        baseModule =
          if baseConfigModule != null then
            baseConfigModule args
          else
            { };
      in
      baseModule
      // {
        config = lib.mkMerge [
          (baseModule.config or { })
          {
            systemd.services.site-c-storage-endpoint-routes = {
              description = "Install site-c storage Nebula endpoint routes on c-router-policy";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              path = [
                pkgs.coreutils
                pkgs.gawk
                pkgs.iproute2
                pkgs.python3
              ];
              serviceConfig.Type = "oneshot";
              script = ''
                set -euo pipefail

                endpoint4='${endpoint4}'
                endpoint6='${endpoint6}'

                peer_for() {
                  local iface="$1"
                  local family="$2"
                  local cidr

                  if [ "$family" = 4 ]; then
                    cidr="$(ip -o -4 addr show dev "$iface" scope global | awk '{print $4}' | head -n1)"
                  else
                    cidr="$(ip -o -6 addr show dev "$iface" scope global | awk '{print $4}' | head -n1)"
                  fi

                  python3 - "$cidr" <<'PY'
import ipaddress
import sys

iface = ipaddress.ip_interface(sys.argv[1])
peer = next(addr for addr in iface.network.hosts() if addr != iface.ip)
print(peer)
PY
                }

                install_pair() {
                  local downstream_iface="$1"
                  local upstream_iface="$2"
                  local table="$3"
                  local peer4 peer6

                  peer4="$(peer_for "$upstream_iface" 4)"
                  peer6="$(peer_for "$upstream_iface" 6)"

                  ip rule del iif "$downstream_iface" table "$table" 2>/dev/null || true
                  ip -6 rule del iif "$downstream_iface" table "$table" 2>/dev/null || true
                  ip rule add iif "$downstream_iface" table "$table"
                  ip -6 rule add iif "$downstream_iface" table "$table"
                  ip route replace table "$table" "$endpoint4/32" via "$peer4" dev "$upstream_iface"
                  ip -6 route replace table "$table" "$endpoint6/128" via "$peer6" dev "$upstream_iface"
                }

                install_pair downstream-nas up-nas-storage 2003
                install_pair down-printer up-prn-sto 2004
              '';
            };
          }
        ];
      };
  };
}
