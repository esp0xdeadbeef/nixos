{ config, lib, pkgs, ... }:
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

  stagedSecrets = lib.listToAttrs (
    lib.imap0 (i: f: lib.nameValuePair (jwePath i) f) resolvedSecretFiles
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

    boot.initrd.systemd.enable = true;

    # Clevis/Tang handles unlock over initrd networking; do not wait on TPM paths.
    boot.initrd.systemd.tpm2.enable = false;
    boot.kernelParams = lib.mkBefore [ "systemd.tpm2_wait=0" ];
    systemd.tpm2.enable = false;

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

    boot.initrd.systemd.initrdBin = lib.mkIf cfg.wifi.enable (with pkgs; [
      coreutils
      gnugrep
      gnused
      iw
      iproute2
      kmod
      util-linux
      wpa_supplicant
    ]);

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
        Type = "forking";
        PIDFile = "/run/initrd-wpa_supplicant.pid";
        RemainAfterExit = true;
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
          if wpa_cli -p /run/wpa_supplicant -i '${cfg.wifi.interface}' status 2>/dev/null \
              | grep -q 'wpa_state=COMPLETED'; then
            associated=1
            break
          fi
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
