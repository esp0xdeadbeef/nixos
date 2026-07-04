{ config
, lib
, outPath
, ...
}:

let
  runtimeReservationsFile = "/run/secrets/s-router-prod-vlan2-reservations.json";
  runtimeUnboundLocalFile = "/run/unbound/s-router-prod-vlan2-local.conf";

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
              def reservation_objects:
                $reservations[0]
                | ..
                | objects
                | select(."hw-address" != null and ."ip-address" != null);

              def masked_reservations:
                [
                  reservation_objects
                  |
                    {
                      "hw-address": ."hw-address",
                      "ip-address": ."ip-address"
                    }
                    + (
                      .hostname as $hostname
                      | if ($hostname != null and ($publicHostnames | index($hostname)) != null) then
                        { hostname: .hostname }
                      else
                        {}
                      end
                    )
                ]
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

        generateUnboundLocalData = pkgs.writeShellScript "gen-s-router-prod-vlan2-unbound-local-data" ''
          set -euo pipefail

          secret=${lib.escapeShellArg runtimeReservationsFile}
          out=${lib.escapeShellArg runtimeUnboundLocalFile}

          if [ ! -r "$secret" ]; then
            echo "[dns] ERROR: runtime reservation secret $secret missing" >&2
            exit 1
          fi

          mkdir -p "$(${pkgs.coreutils}/bin/dirname "$out")"
          tmp="$(${pkgs.coreutils}/bin/mktemp "$out.XXXXXX")"

          ${pkgs.jq}/bin/jq -r '
            def reservation_objects:
              ..
              | objects
              | select(.hostname != null and ."ip-address" != null);

            def safe_hostname:
              type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$");

            def safe_ipv4:
              type == "string" and test("^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+$");

            [
              reservation_objects
              | select(.hostname | safe_hostname)
              | select(."ip-address" | safe_ipv4)
              | {
                  hostname: (.hostname | sub("[.]$"; "")),
                  address: ."ip-address"
                }
            ]
            | unique_by(.hostname, .address)
            | sort_by(.hostname, .address)
            | .[]
            | . as $record
            | "local-data: \"" + $record.hostname + ".lan. A " + $record.address + "\"",
              "local-data-ptr: \"" + $record.address + " " + $record.hostname + ".lan.\""
          ' "$secret" > "$tmp"

          ${pkgs.coreutils}/bin/mv "$tmp" "$out"
        '';
      in
      {
        systemd.services.gen-kea-vlan2.serviceConfig.ExecStartPost = applyReservations;

        services.unbound.settings.server = {
          local-zone = lib.mkBefore [
            "lan. static"
            "1.168.192.in-addr.arpa. static"
          ];
          include = lib.mkAfter [ runtimeUnboundLocalFile ];
        };

        systemd.services.gen-s-router-prod-vlan2-unbound-local-data = {
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
          after = [ "gen-s-router-prod-vlan2-unbound-local-data.service" ];
          requires = [ "gen-s-router-prod-vlan2-unbound-local-data.service" ];
        };
      };
  };
}
