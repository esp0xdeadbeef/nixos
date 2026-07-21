{ lib, ... }:

let
  runtimeMacSecretFile = "/run/secrets/s-nebula-container-mac";
  sNebulaContainerAddress = "192.168.3.10";
  sNebulaContainerHostname = "s-nebula-container";
in
{
  containers.access-vlan3.config =
    { pkgs, ... }:
    let
      applyReservation = pkgs.writeShellScript "apply-s-router-prod-vlan3-kea-reservation" ''
        set -euo pipefail

        cfg=/run/etc/kea/vlan3.json
        secret=${lib.escapeShellArg runtimeMacSecretFile}

        if [ ! -s "$cfg" ]; then
          echo "[kea] ERROR: renderer output $cfg missing before VLAN3 reservation override" >&2
          exit 1
        fi

        if [ ! -r "$secret" ]; then
          echo "[kea] ERROR: runtime MAC secret $secret missing" >&2
          exit 1
        fi

        tmp="$(${pkgs.coreutils}/bin/mktemp "$cfg.XXXXXX")"
        ${pkgs.jq}/bin/jq \
          --rawfile mac "$secret" \
          --arg ip ${lib.escapeShellArg sNebulaContainerAddress} \
          --arg hostname ${lib.escapeShellArg sNebulaContainerHostname} \
          '
            def trim:
              gsub("^[ \t\r\n]+"; "")
              | gsub("[ \t\r\n]+$"; "");

            ($mac | trim) as $hw
            | if ($hw | test("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")) then
                .Dhcp4.subnet4[0].reservations = [
                  {
                    "hw-address": $hw,
                    "ip-address": $ip,
                    hostname: $hostname
                  }
                ]
              else
                error("invalid secret-backed MAC for VLAN3 reservation")
              end
          ' \
          "$cfg" > "$tmp"

        ${pkgs.jq}/bin/jq \
          --arg ip ${lib.escapeShellArg sNebulaContainerAddress} \
          --arg hostname ${lib.escapeShellArg sNebulaContainerHostname} \
          -e '
            .Dhcp4.subnet4[0].reservations as $reservations
            | ($reservations | length) == 1
            and ($reservations[0]."hw-address" | test("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"))
            and $reservations[0]."ip-address" == $ip
            and $reservations[0].hostname == $hostname
          ' "$tmp" >/dev/null

        ${pkgs.coreutils}/bin/mv "$tmp" "$cfg"
      '';
    in
    {
      systemd.services.gen-kea-vlan3.serviceConfig.ExecStartPost = [ applyReservation ];
    };
}
