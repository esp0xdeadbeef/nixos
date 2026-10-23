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

    # Bake the bindings into the initrd instead of relying on
    # `append-initrd-secrets`.
    #
    # With the default loader (systemd-boot) `supportsInitrdSecrets = true`, and
    # secrets are appended to the ESP image at bootloader-install time. On
    # l-portal that append did not produce a usable /.initrd-secrets, so the
    # JWEs were never present in initrd and Tang unlock could not run. Forcing
    # the copy path makes the initrd self-contained and verifiable with
    # `zstd -dc initrd | cpio -it`.
    #
    # Safety note: this copies the JWE into the Nix store. The JWE is a
    # Tang-wrapped ciphertext (already committed to git) and is useless without a
    # reachable Tang, so this does not expose the LUKS key material.
    # mkForce: systemd-boot.hardware?? no -- systemd-boot.nix sets this true
    # unconditionally, so a plain assignment conflicts.
    boot.loader.supportsInitrdSecrets = lib.mkForce false;

    # Upstream's `boot.initrd.clevis.devices.<dev>.secretFile` only accepts a
    # single JWE. We deliberately do NOT set it: instead every binding is staged
    # as its own /etc/clevis/<device>-N.jwe and the service below tries them in
    # order, so per-site bindings can be generated independently.
    boot.initrd.secrets = lib.mkMerge [
      stagedSecrets
      (lib.mkIf cfg.wifi.enable { ${wifiSecretPath} = cfg.wifi.configFile; })
    ];

    # Upstream defines `cryptsetup-clevis-<device>` for its single JWE. Rather
    # than override it, try the additional per-site bindings FIRST: whichever
    # binding answers writes /clevis-<device>/decrypted and upstream's unit is
    # skipped, so a machine booted at cobalt unlocks via the cobalt binding and
    # one booted inside neon via the neon binding, with no requirement that both
    # servers be reachable at the same time.
    boot.initrd.systemd.services.${"clevis-try-bindings-" + cfg.deviceName} = {
      description = "Try per-site Clevis bindings for ${cfg.deviceName}";
      wantedBy = [ "systemd-cryptsetup@${escapedDevice}.service" ];
      wants = [ "network-online.target" ];
      before = [
        "cryptsetup-clevis-${cfg.deviceName}.service"
        "systemd-cryptsetup@${escapedDevice}.service"
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      after = [
        "systemd-modules-load.service"
        "network-online.target"
      ];
      conflicts = [
        "initrd-switch-root.target"
        "shutdown.target"
      ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -u

        out=/clevis-${cfg.deviceName}/decrypted
        [ -s "$out" ] && exit 0

        mkdir -p /clevis-${cfg.deviceName}
        mountpoint -q /clevis-${cfg.deviceName} || mount -t ramfs none /clevis-${cfg.deviceName}
        umask 277

        ${lib.concatMapStrings (f: ''
          if [ ! -s "$out" ] && [ -e "${f}" ]; then
              echo "clevis: trying ${f}" >&2
              if clevis decrypt < "${f}" > "$out.tmp" 2>/dev/null; then
                  mv "$out.tmp" "$out"
                  echo "clevis: unlocked via ${f}" >&2
              else
                  rm -f "$out.tmp"
                  echo "clevis: ${f} could not unlock (tang unreachable?)" >&2
              fi
          fi
        '') resolvedSecretFiles}
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
      '';
    };

    # mkForce: upstream's clevis module also defines this unit (single JWE).
    boot.initrd.systemd.services.${"cryptsetup-clevis-" + cfg.deviceName} = lib.mkForce {
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = cfg.clevisService.restartSec;
      };

      unitConfig.StartLimitBurst = cfg.clevisService.startLimitBurst;
    };

    boot.initrd.kernelModules = cfg.kernelModules;
  };
}
