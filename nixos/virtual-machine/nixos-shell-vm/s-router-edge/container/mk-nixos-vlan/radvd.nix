# mk-nixos-vlan/radvd.nix
{
  pkgs,
  lib,
  args,
}:
{ config, ... }:

let
  wans =
    if args ? wans then args.wans
    else abort "radvd: args.wans must be defined (multiwan mandatory)";

  wan0 =
    if (builtins.length wans) > 0 then builtins.elemAt wans 0
    else abort "radvd: args.wans is empty";

  prefixFile =
    wan0.publicPrefixFile or (abort "radvd: first WAN is missing publicPrefixFile");

  raIfaces = args.raIfaces or map (l: l.iface) (lib.filter (l: l.ra6 or false) args.lans);
  raIfacesStr = lib.concatStringsSep " " raIfaces;

  genScript = pkgs.writeShellScript "v6-ra-generate" ''
    set -euo pipefail

    PREFIX_FILE="${prefixFile}"
    RADVD_CONF="/run/radvd.conf"
    ALLOWED_IFACES="${raIfacesStr}"
    EXPECT_LEN="48"

    if [ ! -r "$PREFIX_FILE" ]; then
      echo "ERROR: missing prefix file $PREFIX_FILE" >&2
      exit 1
    fi

    RAW_PREFIX="$(tr -d ' \t\n\r' < "$PREFIX_FILE")"
    PREFIX_LEN="''${RAW_PREFIX##*/}"
    BASE_PREFIX="''${RAW_PREFIX%%/*}"

    if [ "$PREFIX_LEN" != "$EXPECT_LEN" ]; then
      echo "ERROR: expected /$EXPECT_LEN, got /$PREFIX_LEN" >&2
      exit 1
    fi

    EXPANDED="$(${pkgs.sipcalc}/bin/sipcalc "$BASE_PREFIX" | ${pkgs.gawk}/bin/awk '/Expanded Address/ {print $NF; exit}')"
    IFS=':' read -r H1 H2 H3 _ <<< "$EXPANDED"

    echo "[v6-ra] base prefix: $H1:$H2:$H3::/$EXPECT_LEN"
    : > "$RADVD_CONF"

    for IFACE in $ALLOWED_IFACES; do
      if [ ! -d "/sys/class/net/$IFACE" ]; then
        continue
      fi

      ${pkgs.iproute2}/bin/ip link show "$IFACE" | ${pkgs.gnugrep}/bin/grep -q "UP" || continue

      IDX="$(${pkgs.gnused}/bin/sed -n 's/[^0-9]*\([0-9]\+\)$/\1/p' <<< "$IFACE")"
      [ -n "$IDX" ] || continue

      HEX="$(printf "%04x" "$IDX")"
      PREFIX="$H1:$H2:$H3:$HEX"

      echo "[v6-ra] $IFACE -> $PREFIX::/64"

      ${pkgs.iproute2}/bin/ip -6 addr replace "$PREFIX::1/64" dev "$IFACE"
      ${pkgs.iproute2}/bin/ip -6 route replace "$PREFIX::/64" dev "$IFACE" proto static metric 256

      cat >> "$RADVD_CONF" <<EOF
interface $IFACE {
  AdvSendAdvert on;
  MinRtrAdvInterval 10;
  MaxRtrAdvInterval 30;

  AdvManagedFlag off;
  AdvOtherConfigFlag off;

  prefix $PREFIX::/64 {
    AdvOnLink on;
    AdvAutonomous on;
  };
};
EOF
    done

    ${pkgs.gnugrep}/bin/grep -q '^interface ' "$RADVD_CONF" || {
      echo "ERROR: generated empty $RADVD_CONF" >&2
      exit 1
    }
  '';
in
{
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkDefault 1;

  environment.systemPackages = [
    pkgs.radvd
    pkgs.iproute2
    pkgs.sipcalc
  ];

  systemd.services.radvd-generate-configs = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-networkd.service" ];
    requires = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = genScript;
      RemainAfterExit = true;
    };
  };

  systemd.services.radvd = {
    wantedBy = [ "multi-user.target" ];
    after = [ "radvd-generate-configs.service" ];
    requires = [ "radvd-generate-configs.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.radvd}/bin/radvd -n -C /run/radvd.conf";
      Restart = "always";
      RestartSec = "2s";
    };
  };
}

