{ pkgs, lib, ... }:

let
  genScript = pkgs.writeShellScript "gen-dns-dhcp" ''
    set -euo pipefail

    IN="/run/secrets/vlan2-hostnames-servers.json"
    OUT="/run/unbound-local.conf"
    DOMAIN="lan."

    # Always create file so unbound include never fails
    mkdir -p /run
    : > "$OUT"

    test -r "$IN"

    ${pkgs.jq}/bin/jq -r \
      '.[] | select(.hostname != null and .["ip-address"] != null) |
       "local-data: \"\(.hostname).'"$DOMAIN"' A \(.["ip-address"])\""' \
      "$IN" >> "$OUT"

    ${pkgs.jq}/bin/jq -r \
      '.[] | select(.hostname != null and .["ip-address"] != null) |
       "local-data-ptr: \"\(.["ip-address"]) \(.hostname).'"$DOMAIN"'\""' \
      "$IN" >> "$OUT"
  '';
in
{
  systemd.services.gen-dns-dhcp = {
    description = "Generate Unbound local records from SOPS-provided host map";
    wantedBy = [ "multi-user.target" ];
    before = [ "unbound.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = genScript;
    };
  };

  systemd.services.unbound = {
    after = [ "gen-dns-dhcp.service" ];
    requires = [ "gen-dns-dhcp.service" ];
  };
}
