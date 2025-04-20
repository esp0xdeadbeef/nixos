{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.tpm2.enable = true; # keep your TPM2 settings

  boot.initrd.systemd.services.btrfs_pre_root = {
    description = "Rotate Btrfs subvolumes before root is mounted";
    wantedBy = [ "initrd.target" ]; # pull in on every boot
    after = [ "systemd-cryptsetup@crypted.service" ];
    before = [
      "sysroot.mount"
      "initrd-root-fs.target"
    ];
    unitConfig.DefaultDependencies = "no"; # don’t inherit late deps

    # Anything the script needs inside the initrd
    path = with pkgs; [
      btrfs-progs
      coreutils
      findutils
      util-linux
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = (
        pkgs.writeShellScript "btrfs-pre-root" ''
          #!/usr/bin/env bash
          set -euxo pipefail

          mkdir /btrfs_tmp
          mount /dev/mapper/crypted /btrfs_tmp

          if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
          fi

          delete_subvolume_recursively() {
            IFS=$'\n'
            for i in $(btrfs subvolume list -o "$1" | cut -f9- -d' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
            done
            btrfs subvolume delete "$1"
          }

          for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
            delete_subvolume_recursively "$i"
          done

          btrfs subvolume create /btrfs_tmp/root
          umount /btrfs_tmp
        ''
      );
    };
  };

  environment.persistence."/persist" = {
    enable = true; # NB: Defaults to true, not needed
    hideMounts = true;
    directories = [
      "/root"
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
        mode = "u=rwx,g=rx,o=";
      }
    ];
    files = [
      "/etc/machine-id"
      {
        file = "/var/keys/secret_file";
        parentDirectory = {
          mode = "u=rwx,g=,o=";
        };
      }
    ];
    users.deadbeef = {
      directories = [
        "Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".nixops";
          mode = "0700";
        }
        {
          directory = ".local/share/keyrings";
          mode = "0700";
        }
        {
          directory = ".local/share/lxc";
          mode = "0700";
        }
        ".local/share/direnv"
      ];
      files = [
        ".screenrc"
        # ".zsh_history" # why the fuck does this give errors?
      ];
    };
  };
}
