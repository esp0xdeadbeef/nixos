{ config
, lib
, profiles
, relativeRepo
, ...
}:
{
  imports = [ profiles.nixos.boot.clevis-tang-unlock ];

  # Stage-1 Wi-Fi association for Clevis/Tang unlock. The wpa_supplicant
  # config (with both the neon "diskunlock" and cobalt "cobalt-unlock"
  # networks) is SOPS-managed so the passphrases never sit in cleartext in
  # the repo. sops-nix decrypts it at activation; see l-portal/README.md for
  # the required `nixos-rebuild test` before `switch` on first provision.
  sops.secrets."l-portal-initrd-wifi" = {
    sopsFile = relativeRepo.sourcePath "secrets/l-portal-initrd-wifi.yaml";
    format = "binary";
  };

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
    "qcom/sc8280xp/LENOVO/21BX/qcadsp8280.mbn"
    "qcom/sc8280xp/LENOVO/21BX/qccdsp8280.mbn"
    "qcom/sc8280xp/LENOVO/21BX/qcdxkmsuc8280.mbn"
    "qcom/sc8280xp/LENOVO/21BX/qcslpi8280.mbn"
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
      waitOnlineTimeout = 20;
    };
    wifi = {
      enable = true;
      interface = "wlP6p1s0";
      configFile = config.sops.secrets."l-portal-initrd-wifi".path;
      timeout = 25;
    };
    kernelModules = [
      "michael_mic"
      "ccm"
      "cmac"
      "gcm"
      "arc4"
      "libarc4"
      "mdt_loader"
      "qcom_q6v5_pas"
      "qcom_q6v5"
      "qcom_common"
      "qcom_glink_smem"
      "qcom_pil_info"
      "qcom_sysmon"
      "qmi_helpers"
      "pdr_interface"
      "qcom_pdr_msg"
      "qcom_pd_mapper"
      "qrtr_smd"
      "pwrseq_core"
      "pwrseq_qcom_wcn"
      "pci_pwrctrl_pwrseq"
      "ath11k_pci"
      "ath11k"
      "mac80211"
      "cfg80211"
      "mhi"
      "qrtr_mhi"
      "qrtr"
    ];
  };
}
