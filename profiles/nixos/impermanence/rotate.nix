{ config, lib, pkgs, ... }:

let
  cfg = config.local.impermanence;
in

lib.mkIf cfg.rotateBtrfsRoot.enable {

  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.initrdBin = with pkgs; [
    bash
    btrfs-progs
    coreutils
    findutils
    util-linux
  ];

  boot.initrd.systemd.services.rotateBtrfsRoot = {
    description = "Safely rotate the ephemeral /root Btrfs subvolume";
    wantedBy = [ "initrd.target" ];
    after = [
      "systemd-cryptsetup@${cfg.rootMapperName}.service"
      "systemd-hibernate-resume.service"
    ];
    requires = [ "systemd-cryptsetup@${cfg.rootMapperName}.service" ];
    before = [ "sysroot.mount" ];
    unitConfig = {
      ConditionPathExists = "/dev/mapper/${cfg.rootMapperName}";
      DefaultDependencies = false;
    };
    serviceConfig.Type = "oneshot";
    script = ''
      #!${pkgs.bash}/bin/bash
      set -Eeuo pipefail

      top=/btrfs_tmp
      device=/dev/mapper/${cfg.rootMapperName}
      root="$top/root"
      old_roots="$top/persist/old_roots"
      new_root="$top/.root.new.$$"
      new_root_created=0
      rotated_root=

      finish() {
        rc=$?
        trap - EXIT

        if (( rc != 0 )); then
          if [[ ! -e "$root" ]]; then
            if [[ -n "$rotated_root" && -e "$rotated_root" ]]; then
              echo "Restoring previous root after rotation failure" >&2
              mv -- "$rotated_root" "$root" || true
            fi

            if [[ ! -e "$root" && "$new_root_created" == 1 && -e "$new_root" ]]; then
              echo "Installing prepared root after rotation failure" >&2
              mv -- "$new_root" "$root" || true
            fi
          fi

          if [[ -e "$root" && "$new_root_created" == 1 && -e "$new_root" ]]; then
            btrfs subvolume delete -- "$new_root" || true
          fi
        fi

        if mountpoint -q "$top"; then
          umount "$top" || true
        fi

        exit "$rc"
      }

      trap finish EXIT

      mkdir -p "$top"
      mount -o subvolid=5 "$device" "$top"
      mkdir -p "$old_roots"

      if [[ -e "$root" ]]; then
        if [[ -L "$root" ]] \
          || [[ ! -d "$root" ]] \
          || [[ "$(stat -c %i -- "$root")" != 256 ]] \
          || ! btrfs subvolume show "$root" >/dev/null 2>&1
        then
          echo "Refusing to rotate non-subvolume root: $root" >&2
          exit 1
        fi
      fi

      btrfs subvolume create "$new_root"
      new_root_created=1

      if [[ -e "$root" ]]; then
        timestamp="$(date -u '+%Y-%m-%d_%H-%M-%S')"
        rotated_root="$old_roots/$timestamp"
        suffix=0

        while [[ -e "$rotated_root" ]]; do
          suffix=$((suffix + 1))
          rotated_root="$old_roots/''${timestamp}-$suffix"
        done

        mv -- "$root" "$rotated_root"
        touch -- "$rotated_root"
      fi

      mv -- "$new_root" "$root"
      new_root_created=0
      btrfs filesystem sync "$top"

      umount "$top"
      trap - EXIT
    '';
  };

  systemd.services.pruneBtrfsRoots = {
    description = "Prune old ephemeral Btrfs root subvolumes";
    after = [ "local-fs.target" ];
    unitConfig = {
      ConditionPathIsDirectory = "${cfg.persistPath}/old_roots";
      RequiresMountsFor = cfg.persistPath;
    };
    path = with pkgs; [
      btrfs-progs
      coreutils
      findutils
    ];
    serviceConfig = {
      Type = "oneshot";
      IOSchedulingClass = "idle";
    };
    script = ''
      set -u

      old_roots=${lib.escapeShellArg "${cfg.persistPath}/old_roots"}
      max_age_days=30
      max_roots=30

      is_subvolume() {
        local path="$1"

        [[ -d "$path" ]] \
          && [[ ! -L "$path" ]] \
          && [[ "$(stat -c %i -- "$path")" == 256 ]] \
          && btrfs subvolume show "$path" >/dev/null 2>&1
      }

      delete_old_root() {
        local candidate="$1"

        case "$candidate" in
          "$old_roots"/*) ;;
          *)
            echo "Refusing path outside old_roots: $candidate" >&2
            return 0
            ;;
        esac

        if ! is_subvolume "$candidate"; then
          echo "Skipping non-subvolume: $candidate" >&2
          return 0
        fi

        if ! btrfs subvolume delete \
          --recursive \
          --commit-after \
          -- "$candidate"
        then
          echo "Could not delete old root: $candidate" >&2
        fi

        return 0
      }

      while IFS= read -r -d "" candidate; do
        delete_old_root "$candidate"
      done < <(
        find "$old_roots" \
          -mindepth 1 \
          -maxdepth 1 \
          -mtime "+$max_age_days" \
          -print0
      )

      kept=0
      while IFS= read -r -d "" entry; do
        candidate="''${entry#* }"

        if ! is_subvolume "$candidate"; then
          continue
        fi

        if (( kept < max_roots )); then
          kept=$((kept + 1))
        else
          delete_old_root "$candidate"
        fi
      done < <(
        find "$old_roots" \
          -mindepth 1 \
          -maxdepth 1 \
          -printf '%T@ %p\0' \
          | sort -z -nr
      )
    '';
  };

  systemd.timers.pruneBtrfsRoots = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15min";
      OnUnitActiveSec = "1d";
      RandomizedDelaySec = "30min";
    };
  };
}
