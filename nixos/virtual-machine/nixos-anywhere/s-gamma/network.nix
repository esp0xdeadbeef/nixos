{ config, lib, name, pkgs, ... }:
let
  hostName = name;
  networkAddressesService = "${hostName}-network-addresses";
  networkAddressesUnit = "${networkAddressesService}.service";
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;

  networkAddressEnvPath = config.sops.secrets."network/address_env".path;

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  configureNetworkAddresses = pkgs.writeShellApplication {
    name = "${hostName}-configure-network-addresses";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg networkAddressEnvPath}
      interface="''${NETWORK_INTERFACE:-ens3}"

      if [ ! -r "$env_file" ]; then
        echo "network address env is missing: $env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a

      require_env() {
        name="$1"
        if [ -z "$(printenv "$name" || true)" ]; then
          echo "required network address variable is missing: $name" >&2
          exit 1
        fi
      }

      require_env WEB_IPV6
      require_env WEB_IPV6_PREFIX_LENGTH

      if ! printf '%s\n' "$WEB_IPV6_PREFIX_LENGTH" | grep -Eq '^[0-9]+$'; then
        echo "WEB_IPV6_PREFIX_LENGTH must be numeric" >&2
        exit 1
      fi

      ip -6 addr replace "$WEB_IPV6/$WEB_IPV6_PREFIX_LENGTH" dev "$interface"
    '';
  };
in
{
  sops.secrets."network/address_env" = {
    sopsFile = runtimeSopsFile;
    mode = "0400";
    restartUnits = [ networkAddressesUnit ];
  };

  systemd.services.${networkAddressesService} = {
    description = "Configure ${hostName} runtime network addresses from SOPS";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
    };
    preStart = waitForReadableFiles "network addresses" [
      networkAddressEnvPath
    ];
    script = "${lib.getExe configureNetworkAddresses}";
  };
}
