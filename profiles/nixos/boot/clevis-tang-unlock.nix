{ config, lib, pkgs, ... }:
let
  cfg = config.local.boot.clevisTangUnlock;

  networkConfig =
    if cfg.network.address != null then
      { Address = cfg.network.address; }
    else
      { DHCP = "yes"; };

  tangUrl = "http://${cfg.tang.host}:${toString cfg.tang.port}";
  wifiSecretPath = "/run/initrd-wpa_supplicant.conf";
in
{
  options.local.boot.clevisTangUnlock = {
    enable = lib.mkEnableOption "Clevis/Tang unlock for an initrd LUKS device";

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Name of the boot.initrd.luks.devices entry to unlock.";
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Clevis JWE file used to decrypt the generated LUKS key.";
    };

    tang = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Tang server host used for this Clevis binding.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Tang server TCP port used for this Clevis binding.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = tangUrl;
        description = "Rendered Tang URL for documentation and helper scripts.";
      };
    };

    network = {
      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional initrd network interface to configure.";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional static CIDR address. DHCP is used when unset.";
      };

      waitOnlineTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Seconds to wait for initrd network before falling back to passphrase unlock.";
      };
    };

    wifi = {
      enable = lib.mkEnableOption "Wi-Fi association before Clevis/Tang unlock in initrd";

      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = cfg.network.interface;
        description = "Wireless interface to associate in initrd.";
      };

      configFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Host-local wpa_supplicant config copied into initrd secrets.";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Seconds to wait for wpa_supplicant association in initrd.";
      };
    };

    clevisService = {
      restartSec = lib.mkOption {
        type = lib.types.str;
        default = "5s";
        description = "Delay between Clevis unlock retries.";
      };

      startLimitBurst = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Maximum Clevis unlock attempts during initrd boot.";
      };
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional kernel modules required for initrd networking.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretFile != null;
        message = "local.boot.clevisTangUnlock.secretFile must be set when Clevis/Tang unlock is enabled.";
      }
      {
        assertion = !cfg.wifi.enable || cfg.wifi.interface != null;
        message = "local.boot.clevisTangUnlock.wifi.interface must be set when initrd Wi-Fi unlock is enabled.";
      }
      {
        assertion = !cfg.wifi.enable || cfg.wifi.configFile != null;
        message = "local.boot.clevisTangUnlock.wifi.configFile must be set when initrd Wi-Fi unlock is enabled.";
      }
    ];

    boot.initrd.systemd.enable = true;

    # Clevis/Tang handles unlock over initrd networking; do not wait on TPM paths.
    boot.initrd.systemd.tpm2.enable = false;
    boot.kernelParams = lib.mkBefore [ "systemd.tpm2_wait=0" ];
    systemd.tpm2.enable = false;

    boot.initrd.luks.devices.${cfg.deviceName}.allowDiscards = lib.mkDefault true;

    boot.initrd.clevis.enable = true;
    boot.initrd.clevis.useTang = true;
    boot.initrd.clevis.devices.${cfg.deviceName}.secretFile = cfg.secretFile;

    boot.initrd.systemd.network.enable = true;
    boot.initrd.systemd.network.wait-online.enable = true;
    boot.initrd.systemd.network.wait-online.timeout = cfg.network.waitOnlineTimeout;

    boot.initrd.systemd.network.networks = lib.mkIf (cfg.network.interface != null) {
      "10-clevis-unlock" = {
        matchConfig.Name = cfg.network.interface;
        inherit networkConfig;
      };
    };

    boot.initrd.secrets = lib.mkIf cfg.wifi.enable {
      ${wifiSecretPath} = cfg.wifi.configFile;
    };

    boot.initrd.systemd.initrdBin = lib.mkIf cfg.wifi.enable (with pkgs; [
      coreutils
      gnugrep
      iproute2
      wpa_supplicant
    ]);

    boot.initrd.systemd.services.initrd-wifi = lib.mkIf cfg.wifi.enable {
      description = "Associate Wi-Fi for Clevis/Tang unlock";
      wantedBy = [ "sysinit.target" ];
      wants = [ "initrd-nixos-copy-secrets.service" ];
      after = [
        "initrd-nixos-copy-secrets.service"
        "systemd-udev-settle.service"
      ];
      before = [
        "systemd-networkd.service"
        "systemd-networkd-wait-online.service"
        "cryptsetup-pre.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        ip link set '${cfg.wifi.interface}' up
        wpa_supplicant -B -i '${cfg.wifi.interface}' -c '${wifiSecretPath}'

        for _ in $(seq 1 ${toString cfg.wifi.timeout}); do
          if wpa_cli -i '${cfg.wifi.interface}' status | grep -q '^wpa_state=COMPLETED$'; then
            exit 0
          fi
          sleep 1
        done

        wpa_cli -i '${cfg.wifi.interface}' status || true
        exit 1
      '';
    };

    boot.initrd.systemd.services."cryptsetup-clevis-${cfg.deviceName}" = {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = cfg.clevisService.restartSec;
      };

      unitConfig.StartLimitBurst = cfg.clevisService.startLimitBurst;
    };

    boot.initrd.kernelModules = cfg.kernelModules;
  };
}
