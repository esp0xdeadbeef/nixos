{ config
, lib
, pkgs
, outPath
, ...
}:

let
  cfg = config.local.network.private;
  hostName = config.networking.hostName;
  sopsFile = "${outPath}/secrets/${hostName}-default.yaml";
  sopsFileExists = builtins.pathExists sopsFile;
  networkManagerEnabled = config.networking.networkmanager.enable;
  networkdEnabled = config.systemd.network.enable;

  keyFromLine =
    line:
    let
      match = builtins.match "^([A-Za-z0-9_-]+):.*$" line;
    in
    if match == null then null else builtins.elemAt match 0;

  sopsKeys =
    if sopsFileExists then
      lib.filter (key: key != null) (
        map keyFromLine (lib.splitString "\n" (builtins.readFile sopsFile))
      )
    else
      [ ];

  wifiPrefixes =
    lib.filter (prefix: prefix != null) (
      map
        (
          key:
          let
            match = builtins.match "^(wifi-.*)-ssid$" key;
          in
          if match == null then null else builtins.elemAt match 0
        )
        sopsKeys
    );

  hasWifiProfiles = wifiPrefixes != [ ];
  hasWifiMacSecret = lib.elem "wifi-mac" sopsKeys;
  enableNetworkManagerProfiles = cfg.enable && hasWifiProfiles && networkManagerEnabled;

  hasSecret = name: lib.elem name sopsKeys;
  envName = name: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
  envRef = name: "$" + envName name;
  placeholder = name: config.sops.placeholder.${name};

  wifiSecretNames =
    lib.unique (
      lib.flatten (
        map
          (
            prefix:
            [
              "${prefix}-ssid"
              "${prefix}-password"
            ]
            ++ lib.optional (hasSecret "${prefix}-key-mgmt") "${prefix}-key-mgmt"
          )
          wifiPrefixes
      )
      ++ lib.optional cfg.clonedMac.enable "wifi-mac"
    );

  envLines =
    lib.flatten (
      map
        (
          prefix:
          [
            "${envName "${prefix}-ssid"}=${placeholder "${prefix}-ssid"}"
            "${envName "${prefix}-password"}=${placeholder "${prefix}-password"}"
          ]
          ++ lib.optional (hasSecret "${prefix}-key-mgmt")
            "${envName "${prefix}-key-mgmt"}=${placeholder "${prefix}-key-mgmt"}"
        )
        wifiPrefixes
    )
    ++ lib.optional cfg.clonedMac.enable "${envName "wifi-mac"}=${placeholder "wifi-mac"}";

  mkProfile =
    prefix:
    let
      hasKeyMgmt = hasSecret "${prefix}-key-mgmt";
    in
    {
      name = prefix;
      value = {
        connection = {
          id = prefix;
          type = "wifi";
          autoconnect = true;
          autoconnect-priority = 100;
          permissions = "";
        };

        wifi = {
          mode = "infrastructure";
          ssid = envRef "${prefix}-ssid";
        } // lib.optionalAttrs cfg.clonedMac.enable {
          cloned-mac-address = envRef "wifi-mac";
        };

        wifi-security = {
          key-mgmt = if hasKeyMgmt then envRef "${prefix}-key-mgmt" else "sae";
          psk = envRef "${prefix}-password";
        };

        ipv4 = {
          method = "auto";
          may-fail = false;
        };

        ipv6 = {
          method = "auto";
          may-fail = true;
        };
      };
    };
in
{
  options.local.network.private = {
    enable = lib.mkEnableOption "private Wi-Fi profiles from SOPS secrets" // {
      default = true;
    };

    clonedMac.enable = lib.mkOption {
      type = lib.types.bool;
      default = hostName == "l-portal";
      description = "Apply the wifi-mac SOPS secret as NetworkManager's cloned Wi-Fi MAC address.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.enable || !hasWifiProfiles || networkManagerEnabled || networkdEnabled;
          message = "Private Wi-Fi secrets exist in ${sopsFile}, but neither NetworkManager nor systemd-networkd is enabled.";
        }
        {
          assertion = !cfg.enable || !hasWifiProfiles || networkManagerEnabled;
          message = "Private Wi-Fi profile rendering currently supports NetworkManager. ${hostName} has Wi-Fi secrets but NetworkManager is disabled.";
        }
        {
          assertion = !cfg.enable || !hasWifiProfiles || !cfg.clonedMac.enable || hasWifiMacSecret;
          message = "Private Wi-Fi profile secrets in ${sopsFile} require wifi-mac because local.network.private.clonedMac.enable is true.";
        }
        {
          assertion = !cfg.enable || !hasWifiMacSecret || cfg.clonedMac.enable;
          message = "wifi-mac exists in ${sopsFile}, but local.network.private.clonedMac.enable is false. Refusing to clone Wi-Fi MAC on this host.";
        }
      ];
    }

    (lib.mkIf enableNetworkManagerProfiles {
      sops.secrets = lib.genAttrs wifiSecretNames (_: {
        inherit sopsFile;
        owner = "root";
        group = "root";
        mode = "0400";
      });

      sops.templates."networkmanager-private.env" = {
        content = lib.concatStringsSep "\n" envLines + "\n";
        mode = "0400";
        restartUnits = [ "NetworkManager-ensure-profiles.service" ];
      };

      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.sops.templates."networkmanager-private.env".path ];
        profiles = builtins.listToAttrs (map mkProfile wifiPrefixes);
      };

      system.activationScripts.removePersistentPrivateNetworkManagerProfiles = lib.stringAfter [ "etc" ] ''
        for profile in ${lib.escapeShellArgs wifiPrefixes}; do
          rm -f "/etc/NetworkManager/system-connections/$profile.nmconnection"
        done
      '';

      systemd.services.NetworkManager-ensure-profiles = {
        before = [ "NetworkManager-wait-online.service" ];
        wantedBy = [ "NetworkManager-wait-online.service" ];
        unitConfig.ConditionPathExists = config.sops.templates."networkmanager-private.env".path;
      };

      systemd.services.NetworkManager-wait-online.serviceConfig.ExecStart = lib.mkForce [
        ""
        "${pkgs.networkmanager}/bin/nm-online -q -t 120"
      ];
    })
  ];
}
