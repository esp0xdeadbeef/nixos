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

  # Note: TPM is an *additional* unlock path here, never a replacement.
  # Clevis/Tang remains the primary mechanism (see profiles/nixos/boot/
  # clevis-tang-unlock.nix) and both keyslots coexist in the same LUKS header.
  # The clevis profile deliberately disables systemd.tpm2, and that stays:
  # without the Clevis JWE the machine must still boot, so TPM enrollment is
  # only ever a second, optional keyslot added with cryptsetup manually.
  #
  # TPM is working: /dev/tpm0 + /dev/tpmrm0 exist and dmesg reports "using
  # dTPM TPM backend" (tpm2_getcap: TPM 2.0, spec 1.59, manufacturer NTC).
  # A TPM2 keyslot is enrolled with PCR 7, and the token unseals successfully
  # in stage-2 via `systemd-cryptsetup attach ... tpm2-device=auto,headless=1`
  # with no passphrase and no keyfile.
  #
  # It does NOT yet unseal in stage-1: the initrd logs
  #     Failed to unseal secret using TPM2: State not recoverable
  # Same token, same PCR 7 value, same tpm2-tss 4.2.0 and the same systemd
  # 260.5 in both stages, and PCR 7 is unchanged between enrollment and boot
  # (0x89AF18C9...), so this is not a policy/PCR mismatch. What differs is TPM
  # *state*: a running system reports
  #     TPM2_PT_STARTUP_CLEAR.orderly = 1
  # while a freshly power-cycled TPM starts non-orderly, and the QSEECOM dTPM
  # then rejects the session ("State not recoverable" is the TPM2_RC_INITIALIZE
  # family) until a TPM2 Startup has been performed. `systemd.tpm2_wait=1` only
  # waits for the device *node*, which is why adding it did not help.
  #
  # The `tpm2-startup` unit below performs that startup in stage-1 and orders it
  # before the LUKS unlock. It is additive and cannot make a boot worse: if the
  # startup or the unseal still fails, Clevis/Tang (keyFile) or the passphrase
  # still unlock root exactly as before.
  #
  # Ordering: the Clevis `keyFile` stays the primary unlock path, so Tang is
  # tried first and a machine with Tang reachable never needs the TPM.
  # `tpm2-device=auto` is what lets systemd-cryptsetup fall back to the enrolled
  # TPM2 token when Tang is unreachable, with the passphrase prompt last.
  #
  # Ordering: the Clevis `keyFile` stays the primary unlock path, so Tang is
  # tried first and a machine with Tang reachable never needs the TPM.
  # `tpm2-device=auto` is what lets systemd-cryptsetup fall back to the enrolled
  # TPM2 token when Tang is unreachable, with the passphrase prompt last.
  #
  # That option has to be set in hardware-configuration.nix, not here: it does
  # `boot.initrd.luks.devices = lib.mkForce { ... }`, which replaces the whole
  # attrset and therefore discards any contribution made from this module.
  #
  # Stage-1 also needs the TPM2 userspace, and systemd must wait for the device
  # before unsealing. Both are host facts, so they are declared through the
  # clevis profile's `tpm2` option (which this host's bootloader.nix imports)
  # rather than fought against with mkForce here. See bootloader.nix's
  # `local.boot.clevisTangUnlock.tpm2 = "fallback"`.
  boot.initrd.systemd.tpm2.enable = lib.mkForce true;

  # Perform a TPM2 Startup in stage-1 before any LUKS unseal. A power-cycled
  # QSEECOM dTPM is non-orderly and refuses sessions until started, which is
  # what produced "State not recoverable" at the very first unseal attempt.
  # `tpm2_startup -c` is TPM2_Startup(CLEAR) and is harmless on an already
  # started TPM (it returns TPM2_RC_INITIALIZE, which the `|| true` tolerates).
  boot.initrd.systemd.services.tpm2-startup = {
    description = "Start the TPM2 before LUKS unlock";
    wantedBy = [ "sysinit.target" ];
    before = [
      "systemd-cryptsetup@root.service"
      "clevis-try-bindings-root.service"
      "cryptsetup-pre.target"
    ];
    wants = [ "systemd-udev-settle.service" ];
    after = [ "systemd-udev-settle.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # The store path referenced by ${...} is only available in the initrd if the
    # package is part of the initrd closure. `path` is not enough on its own —
    # it sets $PATH but does not pull the derivation in — so tpm2-tools is also
    # added to initrdBin below.
    path = [ pkgs.tpm2-tools pkgs.coreutils pkgs.gnugrep ];
    script = ''
      set -u
      # Wait (briefly) for the dTPM; the node can appear before the backend is
      # ready to accept a TPM2 session.
      for _ in $(seq 1 20); do
        [ -e /dev/tpmrm0 ] && break
        sleep 1
      done
      [ -e /dev/tpmrm0 ] || exit 0

      echo "tpm2-startup: TPM2_Startup(CLEAR)" >&2
      tpm2_startup -c -T device:/dev/tpmrm0 2>&1 || true
      tpm2_getcap -T device:/dev/tpmrm0 properties-variable 2>&1 \
        | grep -A4 TPM2_PT_STARTUP_CLEAR >&2 || true

      # Diagnose the unseal failure precisely instead of guessing: read the SRK
      # handle the token references, and try an actual Unseal-capable session.
      # These lines are cheap and only run in stage-1.
      echo "tpm2-startup: probing SRK 0x81000001" >&2
      if tpm2_readpublic -c 0x81000001 -T device:/dev/tpmrm0 -o /dev/null >&2; then
        echo "tpm2-startup: SRK readable" >&2
      else
        echo "tpm2-startup: SRK NOT readable (rc=$?)" >&2
      fi

      echo "tpm2-startup: probing getrandom" >&2
      if tpm2_getrandom 8 -T device:/dev/tpmrm0 -o /dev/null >&2; then
        echo "tpm2-startup: getrandom OK" >&2
      else
        echo "tpm2-startup: getrandom FAILED (rc=$?)" >&2
      fi
    '';
  };

  # Put the tools the unit calls into the initrd closure.
  boot.initrd.systemd.initrdBin = lib.mkBefore [ pkgs.tpm2-tools ];
}
