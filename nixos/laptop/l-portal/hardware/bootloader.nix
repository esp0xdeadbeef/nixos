{ config
, lib
, pkgs
, profiles
, relativeRepo
, ...
}:
let
  # The initrd wpa_supplicant config is derived from the shared cobalt Wi-Fi
  # seed, never stored as a literal SSID: the AP advertises
  # `derive-ssid(seed, "cobalt-unlock")` (see wifi-ap.nix / wifi-ssids.nix), so
  # the client must run the *same* derivation to find it. Writing the derived
  # config in an activation step means the SSID tracks the seed and the vendored
  # wordlist automatically, exactly like the clevis key is a generated artifact
  # rather than a hand-typed value.
  derivedWifiConf = "/run/l-portal-initrd-wifi.conf";

  deriveSsid = pkgs.writeShellScript "derive-ssid" (
    builtins.readFile (relativeRepo.sourceModule "library/01-general/network/wifi-ssid-derive.sh")
  );
  ssidList = relativeRepo.sourcePath "library/01-general/network/ssids.txt";
in
{
  imports = [ profiles.nixos.boot.clevis-tang-unlock ];

  # The cobalt Wi-Fi seed is provided by profiles.nixos.network.cobalt-wifi-client
  # (sops secret "cobalt-wifi" at /run/secrets/cobalt-wifi). The initrd Wi-Fi
  # config is generated from it at activation time (see the activation script
  # below) instead of being committed as a static blob with literal SSIDs.

  # Derive the initrd wpa_supplicant config from the cobalt seed. `cobalt-unlock`
  # is the unlock plane; its SSID is a pure function of seed:plane, matching the
  # AP. Runs after sops has decrypted the seed and before the initrd is (re)baked
  # by the next `nixos-rebuild switch`/`boot`.
  system.activationScripts.l-portal-initrd-wifi = {
    deps = [ "setupSecrets" ];
    text = ''
      export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.yq-go pkgs.findutils ]}
      seedFile=/run/secrets/cobalt-wifi
      out=${derivedWifiConf}
      if [ -r "$seedFile" ]; then
        umask 077
        seed=$(${pkgs.yq-go}/bin/yq -r '.seed' "$seedFile")
        psk=$(${pkgs.yq-go}/bin/yq -r '.cobalt-unlock.psk' "$seedFile")
        ssid=$(${deriveSsid} "$seed" cobalt-unlock ${ssidList} /dev/null)
        {
          echo 'ctrl_interface=DIR=/run/wpa_supplicant GROUP=0'
          echo 'update_config=0'
          echo 'network={'
          echo "    ssid=\"$ssid\""
          echo "    psk=\"$psk\""
          echo '    key_mgmt=WPA-PSK'
          echo '}'
        } > "$out"
        echo "l-portal-initrd-wifi: derived unlock SSID from seed" >&2
      else
        echo "l-portal-initrd-wifi: $seedFile missing; cannot derive initrd Wi-Fi" >&2
      fi
    '';
  };

  # This host is on the pinned nixos-26.05, which still offers a scripted initrd.
  # The Clevis/Tang + TPM2 chain needs the systemd one (`tpm2-startup`,
  # `clevis-try-bindings-*`, initrd networking), and `clevis-tang-unlock` no
  # longer sets this for us because the option is a removed-option stub on
  # nixos-unstable. The unstable variant of this host does not need it:
  # nixos-unstable always uses the systemd initrd.
  boot.initrd.systemd.enable = true;

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
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 3;

  local.boot.clevisTangUnlock = {
    enable = true;
    deviceName = "root";

    # Root requires BOTH the cobalt Tang server AND this machine's TPM.
    #
    # `"chain"` means the staged JWE is a Clevis `sss` binding with t = 2 over
    # two shares: a `tang` share and a `tpm2` share sealed to PCR 7. Neither one
    # alone can reconstruct the LUKS key, so a detached disk cannot be opened
    # with the TPM alone and the Tang server alone cannot open it either.
    #
    # This module also provides what stage-1 needs for the TPM share:
    # `boot.initrd.systemd.tpm2.enable`, tpm2-tools in the initrd closure, and a
    # `tpm2-startup` unit that runs TPM2_Startup(CLEAR) before the unseal (the
    # QSEECOM dTPM comes up non-orderly after a power cycle).
    #
    # Failure behaviour is intentional: if Wi-Fi/Tang is unreachable the chain
    # cannot be satisfied, so boot falls through to the LUKS passphrase prompt —
    # or use the `manual-unlock` specialisation, which disables Clevis entirely.
    tpm2 = "chain";

    # The chained binding. Generated with
    #   profiles/nixos/boot/clevis-chain-jwe.sh \
    #     --url http://10.2.90.10:7500 --source-jwe hardware/root-cobalt.jwe
    # (the source JWE supplied the already-working Tang keyslot secret, so the
    # LUKS header was not modified). Regenerate it from the neon site when
    # booting there, since a `tpm2` share is local to this machine and the Tang
    # share names one site.
    #
    # Only the chained binding is staged. Staging a plain Tang-only JWE as well
    # would let one factor unlock root and silently defeat the chain.
    secretFiles = [ ./root-cobalt-chain.jwe ];
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
      # Generated by the `l-portal-initrd-wifi` activation script from the cobalt
      # seed (derived SSID), not a committed literal.
      configFile = derivedWifiConf;
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
