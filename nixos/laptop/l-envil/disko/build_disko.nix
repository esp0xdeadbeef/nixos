{ lib
, pkgs
, relativeRepo
, ...
}:

let
  laptopHibernateSwapSize = import (relativeRepo.module "library/disko/laptop-hibernate-swap-size.nix");
  rootLuksDevice = "/dev/disk/by-partlabel/disk-vda-luks";
  rootMapper = "crypted";
  swapLuksDevice = "/dev/disk/by-partlabel/disk-vda-swap";
  swapMapper = "cryptswap";
in
{
  # Root must be unlocked before the swap key can be read from its encrypted
  # persist subvolume. Do not let cryptsetup.target start cryptswap in parallel.
  boot.initrd.luks.devices = lib.mkForce {
    ${rootMapper} = {
      device = rootLuksDevice;
      allowDiscards = true;
      keyFile = lib.mkForce null;
      crypttabExtraOpts = lib.mkAfter [
        "tpm2-device=auto"
        "tpm2-pcrs=7"
        "tries=5"
        "password-cache=yes"
      ];
    };
  };

  boot.initrd.systemd.services.unlockCryptswapFromRoot = {
    description = "Unlock encrypted swap with a key stored on encrypted root";
    wantedBy = [ "initrd.target" ];
    requires = [ "systemd-cryptsetup@${rootMapper}.service" ];
    after = [ "systemd-cryptsetup@${rootMapper}.service" ];
    before = [ "systemd-hibernate-resume.service" ];
    unitConfig.DefaultDependencies = false;
    path = with pkgs; [
      btrfs-progs
      coreutils
      cryptsetup
      util-linux
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -Eeuo pipefail

      root_device=/dev/mapper/${rootMapper}
      swap_device=${swapLuksDevice}
      swap_mapper=${swapMapper}
      mapped_swap=/dev/mapper/$swap_mapper
      persist_mount=/run/cryptswap-key-root
      key_dir="$persist_mount/etc/diskunlock"
      key_file="$key_dir/cryptswap.key"
      new_key="$key_dir/.cryptswap.key.new.$$"

      finish() {
        rc=$?
        trap - EXIT

        if [[ -e "$new_key" ]]; then
          rm -f -- "$new_key"
        fi

        if mountpoint -q "$persist_mount"; then
          umount "$persist_mount" || true
        fi

        exit "$rc"
      }

      trap finish EXIT

      if [[ ! -b "$root_device" ]]; then
        echo "Encrypted root mapper is unavailable; skipping cryptswap setup" >&2
        exit 0
      fi

      if [[ ! -b "$swap_device" ]]; then
        echo "Swap partition is unavailable; continuing without hibernation" >&2
        exit 0
      fi

      root_luks_real="$(readlink -f -- ${rootLuksDevice})"
      swap_luks_real="$(readlink -f -- "$swap_device")"

      if [[ -z "$root_luks_real" ]] \
        || [[ -z "$swap_luks_real" ]] \
        || [[ "$root_luks_real" == "$swap_luks_real" ]]
      then
        echo "Refusing unsafe cryptswap device selection: $swap_device" >&2
        exit 1
      fi

      if cryptsetup status "$swap_mapper" >/dev/null 2>&1; then
        echo "Refusing pre-existing cryptswap mapper not opened by this service" >&2
        exit 1
      fi

      mkdir -p "$persist_mount"
      mount -t btrfs -o subvol=persist "$root_device" "$persist_mount"
      install -d -m 0700 "$key_dir"

      if [[ -s "$key_file" ]] \
        && cryptsetup open \
          --allow-discards \
          --key-file "$key_file" \
          -- "$swap_device" "$swap_mapper"
      then
        swap_type="$(blkid -p -s TYPE -o value "$mapped_swap" 2>/dev/null || true)"

        case "$swap_type" in
          swap | swsuspend)
            echo "Cryptswap opened with the root-stored key"
            ;;
          *)
            echo "Cryptswap has no usable swap header; creating one" >&2
            mkswap -f "$mapped_swap"
            ;;
        esac

        exit 0
      fi

      echo "No usable root-stored cryptswap key; replacing encrypted swap" >&2

      install -m 0400 /dev/null "$new_key"
      dd if=/dev/urandom of="$new_key" bs=64 count=1 conv=fsync status=none

      cryptsetup luksFormat \
        --batch-mode \
        --type luks2 \
        --key-file "$new_key" \
        -- "$swap_device"

      mv -- "$new_key" "$key_file"
      sync -f "$key_dir"

      cryptsetup open \
        --allow-discards \
        --key-file "$key_file" \
        -- "$swap_device" "$swap_mapper"

      mkswap -f "$mapped_swap"
      echo "Cryptswap replaced and opened with a new root-stored key"

      umount "$persist_mount"
      trap - EXIT
    '';
  };

  disko.devices = {
    disk = {
      vda = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              priority = 1; # Needs to be first partition
            };
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            swap = {
              size = laptopHibernateSwapSize { ramGiB = 64; };
              content = {
                type = "luks";
                name = "cryptswap";
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/disk.key";
                };
                content = {
                  type = "swap";
                  discardPolicy = "both";
                  resumeDevice = true;
                };
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  allowDiscards = true;
                  keyFile = "/tmp/disk.key";
                };
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                    };
                    # "/home/deadbeef" = {
                    #   mountOptions = ["compress=zstd"];
                    #   mountpoint = "/home/deadbeef";
                    # };
                    "/nix" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/nix";
                    };
                    # "/games" = {
                    #   mountOptions = ["compress=zstd" "noatime"];
                    #   mountpoint = "/games";
                    # };
                    "/persist" = {
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                      mountpoint = "/persist";
                    };
                  };
                  mountpoint = "/partition-root";
                };
              };
            };
          };
        };
      };
    };
  };
}
