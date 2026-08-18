{ config
, lib
, pkgs
, inputs
, relativeRepo
, ...
}:

let
  cfg = config.local.network.cobalt-wifi-client;

  ssidList = inputs.wifi-ssids.outPath + "/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  envName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  envVar = name: field: "${envName name}_${field}";

  mkEnvLines = lib.concatMapStrings
    (name: ''
      printf '%s=%s\n' '${envVar name "SSID"}' "$(${deriveSsid} "$seed" '${name}' ${ssidList} "$used")" >> /run/cobalt-wifi.env
      printf '%s=%s\n' '${envVar name "PSK"}' "$(${pkgs.yq-go}/bin/yq -r '.["${name}"].psk' /run/secrets/cobalt-wifi)" >> /run/cobalt-wifi.env
    '')
    cfg.networks;

  mkProfile =
    name:
    {
      inherit name;
      value = {
        connection = {
          id = name;
          type = "wifi";
          autoconnect = true;
          autoconnect-priority = cfg.autoconnectPriority;
          permissions = "";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$" + envVar name "SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$" + envVar name "PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
in
{
  options.local.network.cobalt-wifi-client = {
    enable = lib.mkEnableOption "cobalt Wi-Fi client networks from the shared SOPS secret" // {
      default = true;
    };

    networks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "cobalt-clients"
        "cobalt-clients-vpn"
        "cobalt-mgmt"
      ];
      description = "Network keys in secrets/s-router-cobalt-wifi.yaml (unlock is intentionally excluded).";
    };

    autoconnectPriority = lib.mkOption {
      type = lib.types.int;
      default = -10;
      description = "NetworkManager autoconnect priority. Negative so a currently-connected network wins over these declarative networks.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."cobalt-wifi" = {
      sopsFile = relativeRepo.sourcePath "secrets/s-router-cobalt-wifi.yaml";
      key = "";
      path = "/run/secrets/cobalt-wifi";
    };

    systemd.services.cobalt-wifi-env = {
      description = "Extract cobalt Wi-Fi credentials for NetworkManager";
      after = [ "sops-install-secrets.service" ];
      before = [ "NetworkManager-ensure-profiles.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        umask 077
        seed=$(${pkgs.yq-go}/bin/yq -r '.seed' /run/secrets/cobalt-wifi)
        used=/run/cobalt-wifi-used
        rm -f "$used"
        : > /run/cobalt-wifi.env
        ${mkEnvLines}
      '';
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [ "/run/cobalt-wifi.env" ];
      profiles = builtins.listToAttrs (map mkProfile cfg.networks);
    };
  };
}
