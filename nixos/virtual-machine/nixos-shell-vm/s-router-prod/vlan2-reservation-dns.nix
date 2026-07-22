{ lib, relativeRepo, ... }:

let
  prodInventory = import (relativeRepo.module "prod-network/current/inventory.nix");
  vlan3AuthorityRecords =
    prodInventory.realization.nodes."esp0xdeadbeef-site-a-access-vlan3".services.dns.localRecords;
  vlan3AuthorityNames = map (record: record.name) vlan3AuthorityRecords;
  runtimeReservationNamesFile = "/run/secrets/s-router-prod-vlan2-reservation-names.json";
  runtimeUnboundLocalFile = "/run/unbound/s-router-prod-vlan2-local.conf";
in
{
  # TEMPORARY NETWORK-* COMPATIBILITY OVERRIDE.
  #
  # Remove this file, its import, warning, and parity assertion once protected
  # reservation name publication accepts intentional multi-address hostnames
  # and renders the runtime A/PTR data without exposing the protected source in
  # evaluation output or the Nix store.
  containers.access-vlan2.config =
    { pkgs, ... }:
    let
      generateUnboundLocalData = pkgs.writeShellScript "gen-s-router-prod-vlan2-reservation-dns" ''
        set -euo pipefail

        secret=${lib.escapeShellArg runtimeReservationNamesFile}
        out=${lib.escapeShellArg runtimeUnboundLocalFile}

        if [ ! -r "$secret" ]; then
          echo "[dns] ERROR: protected reservation-name source $secret missing" >&2
          exit 1
        fi

        mkdir -p "$(${pkgs.coreutils}/bin/dirname "$out")"
        tmp="$(${pkgs.coreutils}/bin/mktemp "$out.XXXXXX")"

        ${pkgs.jq}/bin/jq \
          --argjson vlan3AuthorityNames ${lib.escapeShellArg (builtins.toJSON vlan3AuthorityNames)} \
          -r '
          def safe_hostname:
            type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_-]*$");

          def safe_ipv4:
            type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$");

          [
            .[]
            | select(.scope == "vlan2")
            | select(.hostname | safe_hostname)
            | select(.ipv4.address | safe_ipv4)
            | {
                hostname: .hostname,
                address: .ipv4.address
              }
          ]
          | unique_by(.hostname, .address)
          | sort_by(.hostname, .address)
          | .[]
          | . as $record
          # Provider-owned forward records must reach their authoritative
          # resolver. Preserve the reservation PTR, but do not let a VLAN 2 A
          # record shadow the exact peer forward-zone.
          | (
              if ($vlan3AuthorityNames | index($record.hostname + ".lan.")) == null
              then "local-data: \"" + $record.hostname + ".lan. A " + $record.address + "\""
              else empty
              end
            ),
            "local-data-ptr: \"" + $record.address + " " + $record.hostname + ".lan.\""
        ' "$secret" > "$tmp"

        ${pkgs.coreutils}/bin/mv "$tmp" "$out"
      '';
    in
    {
      services.unbound.settings.server = {
        local-zone = lib.mkBefore [
          "lan. static"
          "1.168.192.in-addr.arpa. static"
        ];
        include = lib.mkAfter [ runtimeUnboundLocalFile ];
      };

      systemd.services.gen-s-router-prod-vlan2-reservation-dns = {
        wantedBy = [ "multi-user.target" ];
        before = [ "unbound.service" ];
        requiredBy = [ "unbound.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = generateUnboundLocalData;
          RemainAfterExit = true;
        };
      };

      systemd.services.unbound = {
        after = [ "gen-s-router-prod-vlan2-reservation-dns.service" ];
        requires = [ "gen-s-router-prod-vlan2-reservation-dns.service" ];
      };
    };
}
