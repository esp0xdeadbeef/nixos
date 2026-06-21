{ config, lib, ... }:
let
  cfg = config.local.boot.clevisTangUnlock;

  networkConfig =
    if cfg.network.address != null then
      { Address = cfg.network.address; }
    else
      { DHCP = "yes"; };
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
