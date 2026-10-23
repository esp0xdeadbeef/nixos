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
  # the repo.
  #
  # `sops.secrets...path` is /run/secrets/... -- a runtime path. systemd-boot
  # instead *appends* initrd secrets at bootloader-install time, which requires
  # a real /nix/store path, so the plain `.path` cannot be used as configFile
  # (NixOS rejects it: "boot.initrd.secrets values must be unquoted paths").
  #
  # Stage the already-decrypted copy into the store with a pre-build hook
  # instead: `nixos-rebuild test` makes sops-nix decrypt to /run/secrets, and
  # the hook below snapshots that file into the store for the following
  # `nixos-rebuild boot`. See README "Staging the initrd wifi config".
  sops.secrets."l-portal-initrd-wifi" = {
    sopsFile = relativeRepo.sourcePath "secrets/l-portal-initrd-wifi.yaml";
    format = "binary";
  };

  # Only used when the decrypted secret has been staged (see README); the
  # assertion in profiles/nixos/boot/clevis-tang-unlock.nix turns the failure
  # into a readable message if it has not.
  local.boot.clevisTangUnlock.wifi.configFile =
    if builtins.pathExists /run/secrets/l-portal-initrd-wifi then
      builtins.path
        {
          path = /run/secrets/l-portal-initrd-wifi;
          name = "l-portal-initrd-wpa_supplicant.conf";
        }
    else
      null;

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
    enable = true;
    deviceName = "root";
    # One JWE per Tang site, staged together and tried in order at boot. Each is
    # generated from its own site (see clevis-init-jwe.sh --site), so neither
    # server has to be reachable when the other's binding is created.
    #
    # All of them wrap the same LUKS keyslot secret. A JWE whose Tang is
    # unreachable simply fails to decrypt and the next one is tried, so a stale
    # binding is harmless to keep -- regenerate it from its own site later.
    secretFiles = [
      ./root-cobalt.jwe
      ./root-neon.jwe
    ];
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
