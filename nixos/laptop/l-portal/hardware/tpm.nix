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

  # Note: TPM is an *additional* unlock path here, never a replacement.
  # Clevis/Tang remains the primary mechanism (see profiles/nixos/boot/
  # clevis-tang-unlock.nix) and both keyslots coexist in the same LUKS header.
  # The clevis profile deliberately disables systemd.tpm2, and that stays:
  # without the Clevis JWE the machine must still boot, so TPM enrollment is
  # only ever a second, optional keyslot added with cryptsetup manually.
  #
  # TPM is working as of generation 250: /dev/tpm0 + /dev/tpmrm0 exist and
  # dmesg reports "using dTPM TPM backend" (tpm2_getcap: TPM 2.0, spec 1.59,
  # manufacturer NTC). The LUKS keyslot has NOT been enrolled yet. Doing so
  # needs an existing keyslot unlocked, i.e. either the LUKS passphrase or the
  # Clevis key, so it is left as an explicit operator step:
  #
  #   systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 \
  #     /dev/disk/by-partlabel/disk-nvme0n1-luks
  #
  # Verify afterwards that a tpm2 entry appears under `Tokens:` in
  # `cryptsetup luksDump`; an earlier attempt added a keyslot with no token,
  # which would never auto-unlock. That slot was removed again, leaving the
  # original four slots (passphrase + the two Clevis bindings) intact.
}
