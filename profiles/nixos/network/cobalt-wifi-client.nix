{ config
, lib
, pkgs
, inputs
, relativeRepo
, ...
}:

let
  cfg = config.local.network.cobalt-wifi-client;

  ssidList = relativeRepo.sourcePath "library/01-general/network/ssids.txt";
  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourcePath "library/01-general/network/wifi-ssid-derive.sh")
  );

  envName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  envVar = name: field: "${envName name}_${field}";

  mkEnvLines = lib.concatMapStrings
    (net: ''
      printf '%s=%s\n' '${envVar net.name "SSID"}' "$(${deriveSsid} "$seed" '${net.name}' ${ssidList} "$used")" >> /run/cobalt-wifi.env
      printf '%s=%s\n' '${envVar net.name "PSK"}' "$(${pkgs.yq-go}/bin/yq -r '.["${net.name}"].psk' /run/secrets/cobalt-wifi)" >> /run/cobalt-wifi.env
    '')
    cfg.networks;

  # NetworkManager has no per-profile "prefer this band" knob, so 5GHz
  # preference is expressed as two profiles per network: a higher-priority one
  # pinned to band "a" (5GHz) and a lower-priority band "bg" (2.4GHz) fallback.
  # When a 5GHz BSS is in range the higher priority wins; when it is not, the
  # 5GHz profile matches no AP and NM autoconnects the fallback instead.
  mkProfile =
    { suffix, band, priority }:
    net:
    let
      id = net.name + suffix;
    in
    {
      name = id;
      value = {
        connection = {
          inherit id;
          type = "wifi";
          autoconnect = true;
          autoconnect-priority = priority;
          permissions = "";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$" + envVar net.name "SSID";
          inherit band;
        };
        wifi-security = {
          key-mgmt = net.keyMgmt;
          psk = "$" + envVar net.name "PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };

  mkProfiles =
    net: [
      (mkProfile { suffix = ""; band = "a"; priority = net.priority; } net)
      (mkProfile { suffix = "-2g4"; band = "bg"; priority = net.priority - 1; } net)
    ];
in
{
  options.local.network.cobalt-wifi-client = {
    enable = lib.mkEnableOption "cobalt Wi-Fi client networks from the shared SOPS secret" // {
      default = true;
    };

    networks = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Network key in secrets/s-router-cobalt-wifi.yaml (unlock is intentionally excluded).";
          };
          keyMgmt = lib.mkOption {
            type = lib.types.str;
            description = "NetworkManager wifi-security.key-mgmt. The 5GHz Nighthawk radios are SAE (WPA3); the 2.4GHz ALFA is WPA2-PSK.";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = -10;
            description = "NetworkManager autoconnect-priority. Higher wins; negative keeps manually-added (0) connections preferred.";
          };
        };
      });
      default = [
        { name = "cobalt-clients"; keyMgmt = "sae"; priority = -10; }
        { name = "cobalt-clients-vpn"; keyMgmt = "sae"; priority = -20; }
        { name = "cobalt-mgmt"; keyMgmt = "wpa-psk"; priority = -20; }
      ];
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
      path = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
      ];
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
      profiles = builtins.listToAttrs (lib.concatMap mkProfiles cfg.networks);
    };
  };
}
