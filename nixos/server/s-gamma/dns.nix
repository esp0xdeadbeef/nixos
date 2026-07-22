{ config, lib, name, pkgs, relativeRepo, ... }:
let
  hostName = name;
  networkAddressesService = "${hostName}-network-addresses";
  networkAddressesUnit = "${networkAddressesService}.service";
  runtimeSopsFile = relativeRepo.sourcePath "secrets/s-gamma-runtime.yaml";

  dnsKnotConfPath = config.sops.secrets."dns/knot_conf".path;
  dnsZonePath = config.sops.secrets."dns/zone_001".path;
  dnsZone2Path = config.sops.secrets."dns/zone_002".path;
  knotRuntimeZoneDir = "/run/knot/${hostName}-zones";

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  prepareKnotRuntime = pkgs.writeShellApplication {
    name = "${hostName}-prepare-knot-runtime";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      zone_dir=${lib.escapeShellArg knotRuntimeZoneDir}
      zone_001=${lib.escapeShellArg dnsZonePath}
      zone_002=${lib.escapeShellArg dnsZone2Path}

      install -d -m 0750 "$zone_dir"
      install -m 0640 "$zone_001" "$zone_dir/zone_001.db"
      install -m 0640 "$zone_002" "$zone_dir/zone_002.db"
    '';
  };
in
{
  sops.secrets = {
    "dns/knot_conf" = {
      sopsFile = runtimeSopsFile;
      owner = "knot";
      group = "knot";
      mode = "0440";
      restartUnits = [ "knot.service" ];
    };

    "dns/zone_001" = {
      sopsFile = runtimeSopsFile;
      owner = "knot";
      group = "knot";
      mode = "0440";
      restartUnits = [ "knot.service" ];
    };

    "dns/zone_002" = {
      sopsFile = runtimeSopsFile;
      owner = "knot";
      group = "knot";
      mode = "0440";
      restartUnits = [ "knot.service" ];
    };
  };

  services.knot = {
    enable = true;
    checkConfig = false;
    settingsFile = dnsKnotConfPath;
  };

  systemd.services.${networkAddressesService}.before = [ "knot.service" ];

  systemd.services.knot = {
    after = [ networkAddressesUnit ];
    requires = [ networkAddressesUnit ];
    preStart = lib.mkBefore ''
      ${waitForReadableFiles "knot" [
        dnsKnotConfPath
        dnsZonePath
        dnsZone2Path
      ]}
      ${lib.getExe prepareKnotRuntime}
    '';
    serviceConfig.TimeoutStartSec = "5min";
  };

  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
