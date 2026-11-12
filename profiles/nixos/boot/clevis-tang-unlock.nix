{ config, lib, options, pkgs, ... }:
let
  cfg = config.local.boot.clevisTangUnlock;

  networkConfig =
    if cfg.network.address != null then
      { Address = cfg.network.address; }
    else
      { DHCP = "yes"; };

  tangUrl = "http://${cfg.tang.host}:${toString cfg.tang.port}";
  wifiSecretPath = "/run/initrd-wpa_supplicant.conf";

  # Device names are used inside systemd unit names; `root` needs no escaping,
  # but mirror nixos/lib/utils.nix escapeSystemdPath for paths/dashes so a
  # non-trivial deviceName still produces a valid unit.
  escapedDevice = lib.replaceStrings [ "/" "\\" ] [ "-" "-" ] cfg.deviceName;

  # Legacy `secretFile` folds into the list so only `secretFiles` is used
  # downstream. Order is preserved and duplicates are dropped.
  resolvedSecretFiles = lib.unique (
    cfg.secretFiles ++ lib.optional (cfg.secretFile != null) cfg.secretFile
  );

  # Staged into the initrd as /etc/clevis/<device>-N.jwe. Upstream's module only
  # supports one JWE per device, so we stage them ourselves and drive clevis.
  jweName = i: "${cfg.deviceName}-${toString i}";
  jwePath = i: "/etc/clevis/${jweName i}.jwe";

  # Each JWE must live in the Nix store as its own object, not be referenced as
  # a raw path inside the repository checkout. `boot.initrd.secrets` values are
  # baked into the initrd by `initrd-nixos-copy-secrets`, which runs at boot on
  # the target machine -- so the value must already be a store path that is part
  # of the system closure. Passing the repo path through verbatim works only
  # when `nixos-rebuild` runs from a checkout on that same machine; building
  # elsewhere (e.g. l-portal-unstable built on a remote builder) produced an
  # initrd step that failed with
  #   cp: cannot stat '...-source/nixos/laptop/<host>/hardware/root-cobalt-chain.jwe'
  # and aborted bootloader installation. Copying to the store makes the closure
  # self-contained and the build location irrelevant.
  stagedSecrets = lib.listToAttrs (
    lib.imap0
      (
        i: f:
          lib.nameValuePair (jwePath i) (
            builtins.path {
              path = f;
              name = "clevis-${jweName i}.jwe";
            }
          )
      )
      resolvedSecretFiles
  );

  # The paths the JWEs appear at *inside the initrd*, after
  # initrd-nixos-copy-secrets has placed boot.initrd.secrets. The unlock service
  # must read these, not the source paths.
  stagedPaths = lib.imap0 (i: _: jwePath i) resolvedSecretFiles;
in
{
  options.local.boot.clevisTangUnlock = {
    enable = lib.mkEnableOption "Clevis/Tang unlock for an initrd LUKS device";

    deviceName = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Name of the boot.initrd.luks.devices entry to unlock.";
    };

    luksDevice = lib.mkOption {
      type = lib.types.str;
      description = ''
        Backing device for `deviceName`, used when this unit opens the mapping
        itself instead of handing a keyfile to systemd-cryptsetup.

        Defaults to the device recorded in `boot.initrd.luks.devices`.'';
      default = config.boot.initrd.luks.devices.${cfg.deviceName}.device;
      defaultText = lib.literalExpression ''
        config.boot.initrd.luks.devices.''${cfg.deviceName}.device
      '';
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Clevis JWE file used to decrypt the generated LUKS key.

        Deprecated in favour of `secretFiles`; when set it is appended to that
        list. Prefer `secretFiles` so several site-specific bindings can be
        staged independently.
      '';
    };

    secretFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Clevis JWE files tried in order when unlocking the initrd LUKS device.

        Each file is an independent binding (typically one per Tang site), so
        they can be generated separately, at different times, from different
        networks -- a single site only has to be reachable when *its* binding
        is created. At boot the first JWE whose Tang is reachable wins, so a
        machine booted inside neon unlocks via the neon binding and the same
        machine booted at cobalt unlocks via the cobalt binding, with no
        requirement that both servers be reachable at once.

        Every entry must wrap the *same* LUKS keyslot secret; use
        `clevis-init-jwe.sh` per site to add successive bindings.
      '';
    };

    tang = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "Tang server host used for this Clevis binding.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Tang server TCP port used for this Clevis binding.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = tangUrl;
        description = "Rendered Tang URL for documentation and helper scripts.";
      };
    };

    network = {
      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional initrd network interface to configure.";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional static CIDR address. DHCP is used when unset.";
      };

      waitOnlineTimeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Seconds to wait for initrd network before falling back to passphrase unlock.";
      };
    };

    wifi = {
      enable = lib.mkEnableOption "Wi-Fi association before Clevis/Tang unlock in initrd";

      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = cfg.network.interface;
        description = "Wireless interface to associate in initrd.";
      };

      configFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Host-local wpa_supplicant config copied into initrd secrets.";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Seconds to wait for wpa_supplicant association in initrd.";
      };
    };

    clevisService = {
      restartSec = lib.mkOption {
        type = lib.types.str;
        default = "5s";
        description = "Delay between Clevis unlock retries.";
      };

      startLimitBurst = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Maximum Clevis unlock attempts during initrd boot.";
      };
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional kernel modules required for initrd networking.";
    };

    tpm2 = lib.mkOption {
      type = lib.types.enum [
        "disable"
        "fallback"
        "chain"
      ];
      default = "disable";
      description = ''
        How the TPM2 participates in the initrd unlock.

        `"disable"` (the default) is for hosts with no usable TPM: stage-1 gets
        no TPM2 userspace and `systemd.tpm2_wait=0` is passed, so systemd never
        blocks waiting for a device that will not appear.

        `"fallback"` adds the TPM2 stack to stage-1 and a separate legacy
        `systemd-tpm2` LUKS token is allowed to unlock the device on its own,
        via `crypttabExtraOpts = [ "tpm2-device=auto" ]` on the host. Clevis/Tang
        remains first. Use this when the TPM is a *convenience* path.

        `"chain"` is for a JWE whose Clevis pin is `sss` with `t >= 2` over a
        Tang share *and* a `tpm2` share, i.e. the device opens only when the
        Tang server answers AND this machine's TPM unseals its share, because
        `clevis decrypt` cannot reconstruct the secret from one share alone.
        Stage-1 then needs the full TPM2 stack plus `TPM2_Startup` before the
        unseal, which this module provides. A host using `"chain"` must NOT
        also set `tpm2-device=auto` in `crypttabExtraOpts`: a legacy
        `systemd-tpm2` token would let the TPM unlock the disk by itself and
        collapse the two factors back into one.

        Generate a chained binding with `clevis-chain-jwe.sh` in this directory.
        When Tang is unreachable the unseal fails by design, and boot falls
        through to the LUKS passphrase prompt (or the `manual-unlock`
        specialisation, where Clevis is disabled entirely).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretFiles != [ ] || cfg.secretFile != null;
        message = "local.boot.clevisTangUnlock.secretFiles (or the legacy secretFile) must be set when Clevis/Tang unlock is enabled.";
      }
      {
        assertion = !cfg.wifi.enable || cfg.wifi.interface != null;
        message = "local.boot.clevisTangUnlock.wifi.interface must be set when initrd Wi-Fi unlock is enabled.";
      }
      {
        assertion = !cfg.wifi.enable || cfg.wifi.configFile != null;
        message = "local.boot.clevisTangUnlock.wifi.configFile must be set when initrd Wi-Fi unlock is enabled.";
      }
    ];

    # NOTE: `boot.initrd.systemd.enable` is deliberately not set here. This
    # chain requires the systemd initrd, but nixos-unstable (>=26.11) turned it
    # into a removed-option stub (`mkRemovedOptionModule`), so *defining* it
    # there is an evaluation error -- and it cannot be detected with `options ?`
    # because the stub is still present. Stable (26.05) hosts that import this
    # module therefore request the systemd initrd themselves.
    # Whether a TPM2 keyslot may be used as an unlock fallback is a property of
    # the *host* (does it have a working TPM with an enrolled token?), not of the
    # Clevis binding. Setting it unconditionally here used to force
    # `systemd.tpm2_wait=0` onto hosts that did have a TPM, which then unsealed
    # before the device had probed. Hosts with a TPM opt in via `tpm2 =
    # "fallback"`; see nixos/laptop/l-portal/hardware/tpm.nix.
    boot.initrd.systemd.tpm2.enable = lib.mkDefault (cfg.tpm2 != "disable");
    systemd.tpm2.enable = lib.mkDefault (cfg.tpm2 != "disable");
    # Exactly one value is ever emitted: `tpm2_wait=0` when the host has no TPM
    # (never block initrd on a device that will not appear), `tpm2_wait=1` when
    # it does (initrd must wait for the device before unsealing, otherwise the
    # unseal runs too early and fails with ENOENT). Emitting both — which is what
    # appending with mkAfter used to do — made the effective value depend on
    # systemd's last-wins parsing across two separate command lines.
    boot.kernelParams =
      if cfg.tpm2 != "disable" then [ "systemd.tpm2_wait=1" ] else [ "systemd.tpm2_wait=0" ];

    # ---------------------------------------------------------------------
    # TPM2 readiness in stage-1 (shared by every host that uses the TPM).
    # ---------------------------------------------------------------------
    # `clevis-decrypt-tpm2` shells out to tpm2_createprimary / tpm2_flushcontext
    # / tpm2_load / tpm2_unseal, and those binaries are only in the initrd if the
    # package is in the initrd *closure*. Setting a unit's `path` is not enough
    # — it only sets $PATH — which is why tpm2-tools goes into initrdBin
    # (merged together with the Wi-Fi tooling further down, since two plain
    # assignments to this option would conflict).
    # boot.initrd.systemd.initrdBin = ... see the mkMerge below.

    # A power-cycled TPM (such as the QSEECOM dTPM on the X13s) is non-orderly
    # and refuses sessions until it has been started, so run TPM2_Startup(CLEAR)
    # before anything tries to unseal. `tpm2_startup -c` is TPM2_Startup(CLEAR)
    # and is harmless on an already-started TPM (it returns TPM2_RC_INITIALIZE,
    # which the `|| true` tolerates).
    boot.initrd.systemd.services.tpm2-startup = lib.mkIf (cfg.tpm2 != "disable") {
      description = "Start the TPM2 before LUKS unlock";
      wantedBy = [ "sysinit.target" ];
      before = [
        "systemd-cryptsetup@${escapedDevice}.service"
        "clevis-try-bindings-${cfg.deviceName}.service"
        "cryptsetup-pre.target"
      ];
      wants = [ "systemd-udev-settle.service" ];
      after = [ "systemd-udev-settle.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.tpm2-tools pkgs.coreutils pkgs.gnugrep ];
      script = ''
        set -u
        for _ in $(seq 1 20); do
          [ -e /dev/tpmrm0 ] && break
          sleep 1
        done
        [ -e /dev/tpmrm0 ] || exit 0

        echo "tpm2-startup: TPM2_Startup(CLEAR)" >&2
        tpm2_startup -c -T device:/dev/tpmrm0 2>&1 || true
        tpm2_getcap -T device:/dev/tpmrm0 properties-variable 2>&1 \
          | grep -A4 TPM2_PT_STARTUP_CLEAR >&2 || true
      '';
    };

    boot.initrd.luks.devices.${cfg.deviceName} = {
      allowDiscards = lib.mkDefault true;
      keyFile = lib.mkDefault "/clevis-${cfg.deviceName}/decrypted";
    };

    boot.initrd.clevis.enable = true;
    boot.initrd.clevis.useTang = true;

    # Upstream's `boot.initrd.clevis.devices.<dev>.secretFile` only accepts a
    # single JWE. We deliberately do NOT set it: instead every binding is staged
    # as its own /etc/clevis/<device>-N.jwe and the service below tries them in
    # order, so per-site bindings can be generated independently.
    boot.initrd.secrets = lib.mkMerge [
      stagedSecrets
      (lib.mkIf cfg.wifi.enable { ${wifiSecretPath} = cfg.wifi.configFile; })
    ];

    # Upstream defines `cryptsetup-clevis-<device>` for its single JWE. Rather
    # than override it, try the per-site bindings FIRST: whichever binding
    # answers writes /clevis-<device>/decrypted and upstream's unit is skipped,
    # so a machine booted at cobalt unlocks via the cobalt binding and one booted
    # inside neon via the neon binding, with no requirement that both servers be
    # reachable at the same time.
    boot.initrd.systemd.services.${"clevis-try-bindings-" + cfg.deviceName} = {
      description = "Try per-site Clevis bindings for ${cfg.deviceName}";
      wantedBy = [ "systemd-cryptsetup@${escapedDevice}.service" ];
      # network-online is what actually makes Tang reachable; copy-secrets is
      # what puts the JWEs at their /etc/clevis paths (see initrd-secrets.nix).
      wants = [
        "network-online.target"
        "initrd-nixos-copy-secrets.service"
      ];
      after = [
        "systemd-modules-load.service"
        "network-online.target"
        "initrd-nixos-copy-secrets.service"
      ];
      before = [
        "cryptsetup-clevis-${cfg.deviceName}.service"
        "systemd-cryptsetup@${escapedDevice}.service"
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      conflicts = [
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      unitConfig = {
        DefaultDependencies = "no";
        # Retry budget lives on the unit that actually performs the unlock. The
        # single binding attempt below fails (exit 1) when no staged JWE can be
        # decrypted; systemd then restarts the unit `startLimitBurst` times,
        # `restartSec` apart, before giving up and letting systemd-cryptsetup
        # fall back to the passphrase prompt.
        StartLimitBurst = cfg.clevisService.startLimitBurst;
        # The rate-limit window must be at least as long as the burst it is
        # meant to cap, otherwise the default 10s window trips before the
        # configured retries have been used. One minute per attempt is a
        # generous window that comfortably covers the usual `restartSec` and
        # makes `StartLimitBurst` the binding limit: after that many failed
        # attempts systemd stops restarting and the passphrase fallback runs.
        StartLimitIntervalSec = cfg.clevisService.startLimitBurst * 60;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = cfg.clevisService.restartSec;
      };
      script = ''
        set -u

        out=/clevis-${cfg.deviceName}/decrypted
        [ -s "$out" ] && exit 0

        # Only mount the ramfs once a key is actually produced, so a failed
        # unlock leaves the directory absent (systemd-cryptsetup then falls back
        # to the passphrase prompt instead of reading an empty keyfile).
        #
        # Each JWE carries its own Tang URL, so `clevis decrypt` reaches the
        # right per-site server without us knowing (and possibly guessing
        # wrong) which site we are at. A binding whose Tang is unreachable just
        # fails and the next is tried; if every one fails we exit 1 so
        # `Restart=on-failure` retries while the initrd network settles.
        tmp=$(mktemp)
        for f in ${lib.escapeShellArgs stagedPaths}; do
          echo "clevis: trying $f" >&2
          if clevis decrypt < "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mkdir -p "/clevis-${cfg.deviceName}"
            mountpoint -q "/clevis-${cfg.deviceName}" || mount -t ramfs none "/clevis-${cfg.deviceName}"
            install -m 0400 "$tmp" "$out"
            echo "clevis: unlocked via $f" >&2

            # Open the device HERE, with the decrypted key, rather than leaving
            # it for systemd-cryptsetup to slurp as a keyfile.
            #
            # Why: systemd-cryptsetup does not chain "keyfile then TPM". If a
            # key-file argument is present it keeps failing on that source and
            # never lets `tpm2-device=auto` reach the enrolled token -- measured
            # on this host as `TPM2 operation failed ... State not recoverable`
            # with the keyfile path set, versus a clean unseal with the keyfile
            # field `-`/none. So the Clevis key must not be handed to cryptsetup
            # as the primary key-file; it is used directly to activate the
            # mapping, and cryptsetup is left free to try the TPM token on its
            # own if this mapping is not yet up.
            if cryptsetup status '${cfg.deviceName}' >/dev/null 2>&1; then
              echo "clevis: ${cfg.deviceName} already active" >&2
            elif ${pkgs.cryptsetup}/bin/cryptsetup open \
                   --key-file "$out" \
                   --allow-discards \
                   '${cfg.luksDevice}' '${cfg.deviceName}'; then
              echo "clevis: opened ${cfg.deviceName} with the decrypted key" >&2
            else
              echo "clevis: could not open ${cfg.deviceName}; leaving it to systemd-cryptsetup" >&2
            fi

            rm -f "$tmp"
            exit 0
          fi
          echo "clevis: $f could not unlock" >&2
        done
        rm -f "$tmp"

        # Fail so `Restart=on-failure` retries: Tang may simply not have been
        # reachable yet (address still settling, server busy). Once the restart
        # budget is exhausted systemd leaves the unit failed, this unit's
        # `Before=systemd-cryptsetup@${escapedDevice}.service` ordering ends, and
        # systemd-cryptsetup falls back to the passphrase prompt.
        echo "clevis: no binding could unlock ${cfg.deviceName}; will retry" >&2
        exit 1
      '';
    };

    boot.initrd.systemd.network.enable = true;
    boot.initrd.systemd.network.wait-online.enable = true;
    boot.initrd.systemd.network.wait-online.timeout = cfg.network.waitOnlineTimeout;

    boot.initrd.systemd.network.networks = lib.mkIf (cfg.network.interface != null) {
      "10-clevis-unlock" = {
        matchConfig.Name = cfg.network.interface;
        inherit networkConfig;
      };
    };

    # Both the TPM tooling and the Wi-Fi tooling must land in the initrd
    # *closure*: a unit's `path` only sets $PATH. They are merged into a single
    # `initrdBin` definition because two plain list assignments to the same
    # option conflict.
    boot.initrd.systemd.initrdBin = lib.mkMerge [
      (lib.mkIf (cfg.tpm2 != "disable") [ pkgs.tpm2-tools ])
      (lib.mkIf cfg.wifi.enable (
        with pkgs;
        [
          coreutils
          gnugrep
          gnused
          iw
          iproute2
          kmod
          util-linux
          wpa_supplicant
        ]
      ))
    ];

    boot.initrd.systemd.services.initrd-wifi = lib.mkIf cfg.wifi.enable {
      description = "Associate Wi-Fi for Clevis/Tang unlock";
      wantedBy = [ "sysinit.target" ];
      wants = [ "initrd-nixos-copy-secrets.service" ];
      after = [
        "initrd-nixos-copy-secrets.service"
        "systemd-udev-settle.service"
      ];
      before = [
        "systemd-networkd.service"
        "systemd-networkd-wait-online.service"
        "cryptsetup-pre.target"
      ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        # Type=forking made the whole association wait below dead code: with
        # `wpa_supplicant -B` the parent exits as soon as the daemon is
        # backgrounded, so systemd marked the unit started immediately and
        # released the units ordered after it (systemd-networkd, then
        # systemd-cryptsetup) while the radio was still scanning. Boot then
        # raced: at the 2026-11-06 boot the kernel only associated at t=10.46s,
        # long after networkd had given up and Clevis had fallen through to the
        # passphrase prompt ("no association on 'wlP6p1s0' after 25s" while the
        # kernel log shows `wlP6p1s0: associated` a few hundred ms later).
        #
        # oneshot runs the script to completion, so the association wait is
        # actually part of the unit's start transaction and the ordering of
        # `before = [ systemd-networkd.service ... ]` holds.
        Type = "oneshot";
        RemainAfterExit = true;
        # The daemon is backgrounded by `-B`, not by PIDFile tracking; the pid
        # file is kept only so the log/dump can name it. `-B` writes it inside
        # the script, so no ExecStartPost is needed.
        TimeoutStartSec = 90;
      };
      script = ''
        set -euo pipefail

        dump_debug() {
          echo "--- initrd wifi debug: links ---" >&2
          ip link show >&2 || true
          echo "--- initrd wifi debug: addresses ---" >&2
          ip addr show >&2 || true
          echo "--- initrd wifi debug: modules ---" >&2
          lsmod >&2 || true
          echo "--- initrd wifi debug: rfkill/iw ---" >&2
          iw dev >&2 || true
          echo "--- initrd wifi debug: remoteproc ---" >&2
          for state in /sys/class/remoteproc/remoteproc*/state; do
            [ -e "$state" ] || continue
            echo "$state=$(cat "$state")" >&2
          done
          echo "--- initrd wifi debug: wpa control dir ---" >&2
          ls -la /run /run/wpa_supplicant >&2 || true
          echo "--- initrd wifi debug: wpa log ---" >&2
          sed -n '1,240p' /run/initrd-wpa_supplicant.log >&2 || true
          echo "--- initrd wifi debug: dmesg ---" >&2
          dmesg | grep -Ei 'ath11k|mhi|wlan|wlP|wifi|firmware|remoteproc|qcom|qrtr|pwrseq|wpa|cfg80211|mac80211' >&2 || true
        }

        echo "initrd-wifi: loading configured modules" >&2
        for module in ${lib.escapeShellArgs cfg.kernelModules}; do
          if modprobe "$module"; then
            echo "initrd-wifi: loaded module $module" >&2
          else
            echo "initrd-wifi: module $module failed or is unavailable" >&2
          fi
        done

        echo "initrd-wifi: waiting for interface '${cfg.wifi.interface}'" >&2
        found_interface=0
        for _ in $(seq 1 ${toString cfg.wifi.timeout}); do
          if [ -e '/sys/class/net/${cfg.wifi.interface}' ]; then
            found_interface=1
            break
          fi
          sleep 1
        done
        if [ "$found_interface" != 1 ]; then
          echo "Timed out waiting for Wi-Fi interface '${cfg.wifi.interface}'" >&2
          dump_debug
          exit 1
        fi

        echo "initrd-wifi: interface '${cfg.wifi.interface}' appeared" >&2
        mkdir -p /run/wpa_supplicant
        chmod 700 /run/wpa_supplicant
        ip link set '${cfg.wifi.interface}' up

        echo "initrd-wifi: starting wpa_supplicant for '${cfg.wifi.interface}'" >&2
        wpa_supplicant -B -d \
          -P /run/initrd-wpa_supplicant.pid \
          -f /run/initrd-wpa_supplicant.log \
          -i '${cfg.wifi.interface}' \
          -c '${wifiSecretPath}' \
          -C /run/wpa_supplicant

        # Wait until wpa_supplicant has actually associated. Returning as soon as
        # the daemon is backgrounded used to let the whole initrd race ahead while
        # the radio was still scanning; when association lost that race the
        # Clevis binding had no route to Tang and boot dropped to the passphrase
        # prompt. Blocking here means systemd-networkd (ordered after this unit)
        # only starts once there is a live link to DHCP on.
        echo "initrd-wifi: waiting for association on '${cfg.wifi.interface}'" >&2
        associated=0
        for _ in $(seq 1 ${toString cfg.wifi.timeout}); do
          # `wpa_cli` exits non-zero whenever the daemon is not yet answering
          # (socket not created, interface busy). Under `set -e` a bare command
          # substitution would abort the script, so the status is captured
          # explicitly and a failed poll just means "not associated yet".
          status=$(wpa_cli -p /run/wpa_supplicant -i '${cfg.wifi.interface}' status 2>/dev/null || true)
          case "$status" in
            *wpa_state=COMPLETED*)
              associated=1
              break
              ;;
          esac
          sleep 1
        done
        if [ "$associated" != 1 ]; then
          echo "initrd-wifi: no association on '${cfg.wifi.interface}' after ${toString cfg.wifi.timeout}s" >&2
          dump_debug
          # Do not exit non-zero: an unassociated link must not abort the boot.
          # The clevis retry loop keeps trying, and systemd-cryptsetup falls back
          # to the passphrase prompt if Tang never becomes reachable.
        else
          echo "initrd-wifi: associated on '${cfg.wifi.interface}'" >&2
        fi
      '';
    };

    # Upstream's `cryptsetup-clevis-<device>` (single JWE) is intentionally
    # absent: we never set `boot.initrd.clevis.devices.<dev>.secretFile`, so the
    # upstream module does not define it, and the per-site `clevis-try-bindings-`
    # unit above is the sole producer of `/clevis-<device>/decrypted`. The retry
    # settings live on that unit (see `clevisService`).

    boot.initrd.kernelModules = cfg.kernelModules;
  };
}
