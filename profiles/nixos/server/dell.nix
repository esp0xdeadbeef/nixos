{ inputs
, lib
, config
, options
, pkgs
, ...
}:
let
  cfg = config.local.server.dell;
in
{
  imports = [
    inputs.hardware.nixosModules.common-pc
    inputs.hardware.nixosModules.common-pc-ssd
  ];

  options.local.server.dell.idrac.sops = {
    enable = lib.mkEnableOption "root-readable sops-nix iDRAC credential files for Dell OpenManage wrappers";

    secretNames = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "dell/idrac-host";
        description = "sops-nix secret name for the iDRAC host or address.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "dell/idrac-user";
        description = "sops-nix secret name for the iDRAC user.";
      };

      password = lib.mkOption {
        type = lib.types.str;
        default = "dell/idrac-password";
        description = "sops-nix secret name for the iDRAC password.";
      };
    };
  };

  config = {
    environment.systemPackages = with pkgs; [
      dmidecode
      hwinfo.bin
      ipmitool
      libsmbios
      lshw
      nvme-cli
      pciutils
      smartmontools
      usbutils
    ];

    assertions = [
      {
        assertion = !cfg.idrac.sops.enable || options ? sops;
        message = "local.server.dell.idrac.sops.enable requires sops-nix to be imported.";
      }
    ];

    sops.secrets = lib.mkIf cfg.idrac.sops.enable (
      lib.mapAttrs'
        (
          _name: secretName:
            lib.nameValuePair secretName {
              mode = "0400";
              owner = "root";
              path = "/run/secrets/${secretName}";
            }
        )
        cfg.idrac.sops.secretNames
    );

    local.impermanence.extraSystemDirectories = lib.mkIf (options ? local && options.local ? impermanence) [
      {
        directory = "/var/cache/dell";
        mode = "0750";
      }
      {
        directory = "/var/lib/dell";
        mode = "0750";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/cache/dell 0750 root root -"
      "d /var/cache/dell/dell_dup 0750 root root -"
      "d /var/cache/dell/dell_dup/dsu 0750 root root -"
      "d /var/cache/dell/dell_dup/suu 0750 root root -"
      "d /var/cache/dell/dsu 0750 root root -"
      "d /var/cache/dell/suu 0750 root root -"
      "d /var/lib/dell 0750 root root -"
      "d /var/lib/dell/dsu 0750 root root -"
      "d /var/lib/dell/suu 0750 root root -"
    ];

    specialisation.upgrade-firmware.configuration = {
      system.nixos.tags = [ "upgrade-firmware" ];

      boot.kernelParams = [
        # Some vendor update tools still probe legacy memory ranges. Keep this
        # scoped to the firmware-upgrade boot entry.
        "iomem=relaxed"
      ];

      environment.systemPackages = with pkgs; [
        curl
        dell-openmanage
        dell-system-update
        dell-suu
        efibootmgr
        ethtool
        file
        fwupd
        gnupg
        kmod
        p7zip
        python3
        util-linux
      ];

      local.impermanence.extraSystemDirectories = lib.mkIf (options ? local && options.local ? impermanence) [
        {
          directory = "/var/cache/fwupd";
          mode = "0755";
        }
        {
          directory = "/var/lib/fwupd";
          mode = "0755";
        }
      ];

      services.fwupd.enable = true;

      systemd.tmpfiles.rules = [
        "d /var/cache/fwupd 0755 root root -"
        "d /var/lib/fwupd 0755 root root -"
      ];

      systemd.services.dell-firmware-upgrade-modules = {
        description = "Load Dell firmware update support modules";
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          for module in dcdbas dell_rbu ipmi_msghandler ipmi_devintf ipmi_si acpi_ipmi; do
            if ! ${lib.getExe' pkgs.kmod "modprobe"} "$module"; then
              echo "dell-firmware-upgrade: module $module is not available or could not be loaded" >&2
            fi
          done
        '';
      };
    };
  };
}
