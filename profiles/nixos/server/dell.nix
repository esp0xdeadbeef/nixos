{ inputs, pkgs, ... }: {
  imports = [
    inputs.hardware.nixosModules.common-pc
    inputs.hardware.nixosModules.common-pc-ssd
  ];

  environment.systemPackages = with pkgs; [
    dmidecode
    ipmitool
    libsmbios
    lshw
    nvme-cli
    pciutils
    smartmontools
    usbutils
  ];
}
