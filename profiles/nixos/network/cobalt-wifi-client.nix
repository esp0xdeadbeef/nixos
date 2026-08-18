{ config
, lib
, pkgs
, relativeRepo
, ...
}:

let
  cfg = config.local.network.cobalt-wifi-client;

  envName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  envVar = name: field: "${envName name}_${field}";

  yqExpr = lib.concatStringsSep ", " (
    lib.concatMap
      (name: [
        "\"${envVar name "SSID"}=\" + .[\"${name}\"].ssid"
        "\"${envVar name "PSK"}=\" + .[\"${name}\"].psk"
      ])
      cfg.networks
  );

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
        ${pkgs.yq-go}/bin/yq -r '${yqExpr}' \
          /run/secrets/cobalt-wifi > /run/cobalt-wifi.env
      '';
    };

    networking.networkmanager.ensureProfiles = {
      environmentFiles = [ "/run/cobalt-wifi.env" ];
      profiles = builtins.listToAttrs (map mkProfile cfg.networks);
    };
  };
}
