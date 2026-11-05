{ lib, ... }:
let
  # Out-of-tree Qualcomm QSEECOM fTPM transport, authored by Xilin Wu
  # (sophon@radxa.com) in github:strongtz/linux-radxa-qcom (v7.0.11-qcom).
  # Not submitted upstream and absent from mainline `drivers/char/tpm/`, so it
  # is carried here as a kernel patch series. Verified to apply against the
  # 6.18 kernel nixpkgs builds for l-portal.
  #
  #   0001  qcom_scm: qcom_scm_query_tpm_type() SIP wrapper (svc 0x20, cmd 0x01)
  #   0002  qseecom: register the "qcom.tz.tpm" app -> qcom_qseecom.tpm
  #   0003  tpm_qcom_qsee.c: TPM 2.0 transport over the TZ-shared control area
  patches = [
    ./patches/0001-firmware-qcom-scm-add-tpm-backend-type-query.patch
    ./patches/0002-firmware-qcom-qseecom-register-qcom-tz-tpm.patch
    ./patches/0003-tpm-add-qualcomm-qsee-tpm-transport-driver.patch
  ];
in
{
  boot.kernelPatches = [
    {
      name = "qcom-qsee-tpm";
      patch = patches;

      # QCOM_QSEECOM and QCOM_TZMEM_MODE_SHMBRIDGE are already enabled by the
      # generic aarch64 config; the transport driver itself needs enabling. It
      # *requires* SHMBRIDGE mode: firmware hands back a physical control area
      # that must be shared with TrustZone via qcom_tzmem_shm_bridge_create(),
      # which the generic/memshare TZMEM modes do not do.
      structuredExtraConfig = {
        TCG_QCOM_TPM_QSEE = lib.kernel.yes;
      };
    }
  ];

  # Note: TPM is an *additional* unlock path here, never a replacement.
  # Clevis/Tang remains the primary mechanism (see profiles/nixos/boot/
  # clevis-tang-unlock.nix) and both keyslots coexist in the same LUKS header.
  # The clevis profile deliberately disables systemd.tpm2, and that stays:
  # without the Clevis JWE the machine must still boot, so TPM enrollment is
  # only ever a second, optional keyslot added with cryptsetup manually.
}
