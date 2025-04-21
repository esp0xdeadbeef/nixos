{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:

{
  # boot.initrd.systemd.enable = true;
  boot.initrd.systemd.tpm2.enable = true; # keep your TPM2 settings

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;

  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.initrdBin = with pkgs; [
    util-linux btrfs-progs coreutils findutils
  ];

  boot.initrd.systemd.services.rotateBtrfsRoot = {
    description = "Rotate /root Btrfs subvolume and prune >30 day snapshots";
    wantedBy    = [ "initrd.target" ];
    after       = [ "systemd-cryptsetup@crypted.service" ];
    before      = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";

    # a real script; systemd will write it to a temp file + run it
    script = ''
      #!${pkgs.bash}/bin/bash -euo pipefail
      mkdir /btrfs_tmp
      mount /dev/mapper/crypted /btrfs_tmp
      if [[ -e /btrfs_tmp/root ]]; then
          mkdir -p /btrfs_tmp/persist/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/root "/btrfs_tmp/persist/old_roots/$timestamp/"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      for i in $(find /btrfs_tmp/persist/old_roots/ -mindepth 1 -maxdepth 1 -mtime +1); do
          delete_subvolume_recursively "$i"
      done

      btrfs subvolume create /btrfs_tmp/root
      umount /btrfs_tmp
    '';
  };

  services.openssh = {
    hostKeys = [
      {
        type = "ed25519";
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
      }
    ];
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
