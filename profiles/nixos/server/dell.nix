{ inputs
, lib
, options
, pkgs
, ...
}: {
  imports = [
    inputs.hardware.nixosModules.common-pc
    inputs.hardware.nixosModules.common-pc-ssd
  ];

  environment.systemPackages = with pkgs; [
    dell-system-update
    dell-suu
    dmidecode
    ipmitool
    libsmbios
    lshw
    nvme-cli
    pciutils
    smartmontools
    usbutils
  ];

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
}
