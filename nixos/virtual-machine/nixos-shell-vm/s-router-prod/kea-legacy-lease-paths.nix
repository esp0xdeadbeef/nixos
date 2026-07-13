{ lib, ... }:

let
  vlanContainers = {
    access-vlan2 = "vlan2";
    access-vlan3 = "vlan3";
    access-vlan7 = "vlan7";
  };

  mkContainerOverride =
    _containerName: vlanName:
    { pkgs, ... }:
    let
      cfg = "/run/etc/kea/${vlanName}.json";
      leaseFile = "/var/lib/kea/${vlanName}.leases";
      rewriteLeasePath = pkgs.writeShellScript "rewrite-kea-${vlanName}-lease-path" ''
        set -euo pipefail

        cfg=${lib.escapeShellArg cfg}
        lease_file=${lib.escapeShellArg leaseFile}

        if [ ! -s "$cfg" ]; then
          echo "[kea] ERROR: generated config $cfg missing before lease path rewrite" >&2
          exit 1
        fi

        tmp="$(${pkgs.coreutils}/bin/mktemp "$cfg.XXXXXX")"
        ${pkgs.jq}/bin/jq \
          --arg leaseFile "$lease_file" \
          '.Dhcp4."lease-database".name = $leaseFile' \
          "$cfg" > "$tmp"
        ${pkgs.coreutils}/bin/mv "$tmp" "$cfg"
      '';
    in
    {
      systemd.services."gen-kea-${vlanName}".serviceConfig.ExecStartPost =
        lib.mkAfter [ rewriteLeasePath ];

      systemd.services."kea-dhcp4-${vlanName}".serviceConfig.StateDirectory = "kea";
    };
in
{
  containers = lib.mapAttrs
    (containerName: vlanName: {
      config = mkContainerOverride containerName vlanName;
    })
    vlanContainers;
}
