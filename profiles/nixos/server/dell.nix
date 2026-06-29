{ inputs
, lib
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

  specialisation.upgrade-firmware.configuration = {
    system.nixos.tags = [ "upgrade-firmware" ];

    boot.kernelParams = [
      # Some vendor update tools still probe legacy memory ranges. Keep this
      # scoped to the firmware-upgrade boot entry.
      "iomem=relaxed"
    ];

    environment.systemPackages = with pkgs; [
      curl
      efibootmgr
      ethtool
      file
      gnupg
      kmod
      p7zip
      util-linux
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
