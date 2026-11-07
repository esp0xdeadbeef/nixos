{ lib, pkgs, ... }:
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
  #   0004  accept the dTPM backend (the X13s reports dTPM, not fTPM)
  #
  # 0001-0003 are Xilin Wu's out-of-tree series. 0004 is local: the X13s AS
  # reports QCOM_TPM_TYPE_DTPM (0x6454504d) on qcom.tz.tpm, which 0003 rejects.
  # The transport is backend-neutral (control area comes from the TA via
  # QUERY_INFO_2, command/response cycle is identical), so accepting dTPM is a
  # probe-gate change, not a new protocol.
  #
  # Each file needs its own `kernelPatches` entry: nixpkgs derives the kernel's
  # `patches` list with `map (p: p.patch) kernelPatches`, so `patch` must be a
  # single path. Passing a list here produces a nested list that the patch
  # phase silently drops entries from.
  patches = [
    {
      name = "qcom-qsee-tpm-0001-scm-tpm-type";
      patch = ./patches/0001-firmware-qcom-scm-add-tpm-backend-type-query.patch;
    }
    {
      name = "qcom-qsee-tpm-0002-qseecom-app";
      patch = ./patches/0002-firmware-qcom-qseecom-register-qcom-tz-tpm.patch;
    }
    {
      name = "qcom-qsee-tpm-0003-transport-driver";
      patch = ./patches/0003-tpm-add-qualcomm-qsee-tpm-transport-driver.patch;

      # QCOM_QSEECOM and QCOM_TZMEM_MODE_SHMBRIDGE are already enabled by the
      # generic aarch64 config; the transport driver itself needs enabling. It
      # *requires* SHMBRIDGE mode: firmware hands back a physical control area
      # that must be shared with TrustZone via qcom_tzmem_shm_bridge_create(),
      # which the generic/memshare TZMEM modes do not do.
      structuredExtraConfig = {
        TCG_QCOM_TPM_QSEE = lib.kernel.yes;
      };
    }
    {
      name = "qcom-qsee-tpm-0004-dtpm-backend";
      patch = ./patches/0004-tpm-qcom-qsee-support-dtpm-backend.patch;
    }
  ];
in
{
  boot.kernelPatches = patches;

  # No kernel param needed: the dTPM backend is accepted by default. Passing
  # `tpm_qcom_qsee.allow_dtpm=0` restores the original fTPM-only behaviour.

  # The QSEECOM transport above is all that is X13s-specific. Everything else
  # about how the TPM is used at boot is generic and lives in
  # profiles/nixos/boot/clevis-tang-unlock.nix, driven by
  # `local.boot.clevisTangUnlock.tpm2`.
  #
  # This host sets that option to "chain" (see hardware/bootloader.nix): the
  # staged Clevis JWE is an `sss` binding with t = 2 over a Tang share and a
  # `tpm2` share, so root opens only when the Tang server answers AND this
  # machine's TPM unseals its share. The module supplies what stage-1 needs for
  # that: boot.initrd.systemd.tpm2.enable, tpm2-tools in the initrd closure, and
  # a `tpm2-startup` unit running TPM2_Startup(CLEAR) before the unseal (a
  # power-cycled QSEECOM dTPM is non-orderly and rejects sessions until started,
  # which surfaced as "TPM2 operation failed ... State not recoverable").
  #
  # The earlier setup here was a standalone systemd-tpm2 keyslot unlocked with
  # `tpm2-device=auto` in crypttab. That is deliberately gone: it would let the
  # TPM unlock the disk on its own and collapse the chain back into a single
  # factor. See hardware-configuration.nix, which sets neither `keyFile` nor
  # `tpm2-device=auto`.
  #
  # If the chain cannot be satisfied (no Wi-Fi, Tang down, PCRs changed by a
  # firmware update), boot falls through to the LUKS passphrase prompt, or the
  # `manual-unlock` specialisation can be used, which disables Clevis entirely.
}
