{ config
, pkgs
, lib
, ...
}:
{
  hardware.deviceTree = {
    enable = true;
    filter = lib.mkDefault "sc8280xp-lenovo-thinkpad-x13s*.dtb";
    name = lib.mkDefault "qcom/sc8280xp-lenovo-thinkpad-x13s.dtb";
  };

  boot.kernelParams = lib.mkBefore [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "arm64.nopauth"
    "pci=realloc,resource_alignment=21@0006:00:00.0"
    "systemd.tpm2_wait=0"
  ];

  boot.initrd.kernelModules = [
    "nvme"
    "phy-qcom-qmp-pcie"

    "i2c-core"
    "i2c-hid"
    "i2c-hid-of"
    "i2c-qcom-geni"

    "leds_qcom_lpg"
    "pwm_bl"
    "qrtr"
    "pmic_glink_altmode"
    "gpio_sbu_mux"
    "phy-qcom-qmp-combo"
    "gpucc_sc8280xp"
    "dispcc_sc8280xp"
    "phy_qcom_edp"
    "panel-edp"
    "msm"
  ];

  boot.initrd.extraFirmwarePaths = [
    "qcom/a660_sqe.fw"
    "qcom/a660_gmu.bin"
  ];

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  boot.initrd.systemd.tpm2.enable = false;
  systemd.tpm2.enable = false;
}
