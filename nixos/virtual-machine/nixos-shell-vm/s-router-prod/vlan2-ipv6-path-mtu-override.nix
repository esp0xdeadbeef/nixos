{ lib, pkgs, ... }:
let
  upstreamPathMtu = 1492;

  applyAdvertisedPathMtu = ''
    set -euo pipefail

    config_file=/run/radvd-lan2.conf

    if ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]*AdvLinkMTU[[:space:]]+' "$config_file"; then
      if ! ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]*AdvLinkMTU[[:space:]]+${toString upstreamPathMtu};[[:space:]]*$' "$config_file"; then
        echo "refusing to replace an unexpected renderer-owned AdvLinkMTU" >&2
        exit 1
      fi
    else
      temporary_file="$(${pkgs.coreutils}/bin/mktemp /run/radvd-lan2.conf.XXXXXX)"
      cleanup() {
        ${pkgs.coreutils}/bin/rm -f "$temporary_file"
      }
      trap cleanup EXIT INT TERM

      ${pkgs.gawk}/bin/awk -v mtu=${toString upstreamPathMtu} '
        /^[[:space:]]*AdvSendAdvert[[:space:]]+on;[[:space:]]*$/ {
          print
          print "  AdvLinkMTU " mtu ";"
          inserted = 1
          next
        }
        { print }
        END {
          if (!inserted) {
            exit 42
          }
        }
      ' "$config_file" > "$temporary_file"

      ${pkgs.radvd}/bin/radvd --configtest --config "$temporary_file"
      ${pkgs.coreutils}/bin/install -m 0644 "$temporary_file" "$config_file"
    fi

    ${pkgs.radvd}/bin/radvd --configtest --config "$config_file"
  '';
in
{
  # TEMPORARY NETWORK-RENDERER-NIXOS COMPATIBILITY OVERRIDE.
  #
  # The renderer already applies its inet-family TCP MSS clamp at the core
  # PPPoE boundary. Advertise the same path MTU so IPv6 UDP/QUIC does not need
  # to discover the 1492-byte PPPoE limit through ICMPv6 packet-too-big first.
  # Remove this entire file, its import, warning, and parity assertion once the
  # renderer propagates the uplink path MTU into the access RA itself.
  containers.access-vlan2.config.systemd.services."radvd-generate-lan2".postStart =
    lib.mkBefore applyAdvertisedPathMtu;
}
