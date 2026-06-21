{ config
, pkgs
, lib
, profiles
, ...
}:
let
  initrdWifiConfig = /persist/etc/diskunlock/wpa_supplicant.conf;
  hasInitrdWifiConfig = builtins.pathExists initrdWifiConfig;
in
{
  imports = [ profiles.nixos.boot.clevis-tang-unlock ];

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

  boot.kernelPatches = [
    {
      name = "enable-iso9660-joliet";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        JOLIET = yes;
        ZISOFS = yes;
      };
    }
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
    "qcom/sc8280xp/LENOVO/21BX/qcdxkmsuc8280.mbn"
  ];

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  boot.initrd.systemd.tpm2.enable = false;
  systemd.tpm2.enable = false;

  local.boot.clevisTangUnlock = {
    enable = builtins.pathExists ./root.jwe;
    deviceName = "root";
    secretFile =
      if builtins.pathExists ./root.jwe then
        ./root.jwe
      else
        null;
    tang = {
      host = "192.168.1.75";
      port = 7500;
    };
    network = {
      interface = "wlP6p1s0";
      waitOnlineTimeout = 30;
    };
    wifi = {
      enable = hasInitrdWifiConfig;
      interface = "wlP6p1s0";
      configFile =
        if hasInitrdWifiConfig then
          initrdWifiConfig
        else
          null;
      timeout = 30;
    };
    kernelModules = [
      "ath11k_pci"
      "ath11k"
      "mac80211"
      "cfg80211"
      "mhi_pci_generic"
      "mhi"
      "qrtr_mhi"
      "qrtr"
    ];
  };
}
