{ config
, lib
, outPath
, ...
}:

let
  runtimeReservationsFile = "/run/secrets/s-router-prod-vlan2-reservations.json";

  # Hostnames are private by default. Keep only names that are acceptable in the
  # rendered runtime Kea file; all other reservation hostnames are dropped.
  publicHostnames = [
    "s-tau"
  ];
  publicHostnamesJson = builtins.toJSON publicHostnames;
in
{
  sops.secrets.s-router-prod-vlan2-reservations-json = {
    sopsFile = "${outPath}/secrets/vlan2-hostnames-servers.json.age";
    format = "binary";
    path = runtimeReservationsFile;
  };

  containers.access-vlan2 = {
    bindMounts.${runtimeReservationsFile} = {
      hostPath = config.sops.secrets.s-router-prod-vlan2-reservations-json.path;
      isReadOnly = true;
    };

    config =
      { pkgs, ... }:
      let
        applyReservations = pkgs.writeShellScript "apply-s-router-prod-vlan2-kea-reservations" ''
          set -euo pipefail

          cfg=/run/etc/kea/vlan2.json
          secret=${lib.escapeShellArg runtimeReservationsFile}

          if [ ! -s "$cfg" ]; then
            echo "[kea] ERROR: renderer output $cfg missing before VLAN2 reservation override" >&2
            exit 1
          fi

          if [ ! -r "$secret" ]; then
            echo "[kea] ERROR: runtime reservation secret $secret missing" >&2
            exit 1
          fi

          tmp="$(${pkgs.coreutils}/bin/mktemp "$cfg.XXXXXX")"
          ${pkgs.jq}/bin/jq \
            --argjson publicHostnames ${lib.escapeShellArg publicHostnamesJson} \
            --slurpfile reservations "$secret" \
            '
              def masked_reservations:
                $reservations[0]
                | map(
                    {
                      "hw-address": ."hw-address",
                      "ip-address": ."ip-address"
                    }
                    + (
                      if (.hostname != null and ($publicHostnames | index(.hostname)) != null) then
                        { hostname: .hostname }
                      else
                        {}
                      end
                    )
                  )
                | map(select(."hw-address" != null and ."ip-address" != null))
                | sort_by(."hw-address")
                | group_by(."hw-address")
                | map(.[0])
                | sort_by(."ip-address")
                | group_by(."ip-address")
                | map(.[0]);

              masked_reservations as $masked
              | if ($masked | length) == 0 then
                  error("no valid VLAN2 reservations in runtime secret")
                else
                  .Dhcp4.subnet4[0].reservations = $masked
                end
            ' \
            "$cfg" > "$tmp"

          ${pkgs.jq}/bin/jq \
            --argjson publicHostnames ${lib.escapeShellArg publicHostnamesJson} \
            -e '
            .Dhcp4.subnet4[0].reservations
            | all((has("hostname") | not) or (.hostname as $name | $publicHostnames | index($name) != null))
            ' "$tmp" >/dev/null

          ${pkgs.coreutils}/bin/mv "$tmp" "$cfg"
        '';
      in
      {
        systemd.services.gen-kea-vlan2.serviceConfig.ExecStartPost = applyReservations;
      };
  };
}
