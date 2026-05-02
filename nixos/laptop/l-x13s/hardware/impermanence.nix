{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.initrd.systemd.enable = true;
  boot.initrd.systemd.tpm2.enable = true;

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/nix".neededForBoot = true;

  boot.initrd.systemd.initrdBin = with pkgs; [
    bash
    btrfs-progs
    coreutils
    findutils
    util-linux
  ];

  boot.initrd.systemd.services.rotateBtrfsRoot = {
    description = "Rotate /root Btrfs subvolume and prune >30 day snapshots";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@root.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = ''
      #!${pkgs.bash}/bin/bash -euo pipefail
      mkdir /btrfs_tmp
      mount /dev/mapper/root /btrfs_tmp
      if [[ -e /btrfs_tmp/root ]]; then
          mkdir -p /btrfs_tmp/persist/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
          old_root="/btrfs_tmp/persist/old_roots/$timestamp"
          suffix=0
          while [[ -e "$old_root" ]]; do
              suffix=$((suffix + 1))
              old_root="/btrfs_tmp/persist/old_roots/''${timestamp}_$suffix"
          done
          mv /btrfs_tmp/root "$old_root"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      if [[ -d /btrfs_tmp/persist/old_roots ]]; then
          for i in $(find /btrfs_tmp/persist/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30); do
              delete_subvolume_recursively "$i"
          done

          # The X13s initrd may not have reliable wall-clock time early in boot.
          # Keep a bounded number of old roots even when mtime pruning cannot work.
          while read -r i; do
              delete_subvolume_recursively "/btrfs_tmp/persist/old_roots/$i"
          done < <(find /btrfs_tmp/persist/old_roots/ -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -r | tail -n +31)
      fi

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

  systemd.tmpfiles.rules = [
    "d /persist/var/lib 0755 root root -"
  ];

  environment.persistence."/persist" = {
    enable = true;
    hideMounts = true;
    directories = [
      "/root"
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/sbctl"
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
        file = "/var/cache/locatedb";
        parentDirectory.mode = "u=rwx,g=rx,o=";
      }
    ];
    users.deadbeef = {
      directories = [
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Videos"
        "firefox-pentest-profile"
        "github"
        "pentest"
        ".ZAP/plugin"
        ".cache"
        ".config/Code"
        ".config/Signal"
        ".config/VSCodium"
        ".config/autorandr"
        ".config/chromium"
        ".config/gh"
        ".config/google-chrome"
        ".config/legcord"
        ".config/maestral"
        ".config/obsidian"
        ".config/remmina"
        ".config/sops"
        ".continue"
        ".dropbox"
        ".dropbox-dist"
        ".local/share/PrismLauncher"
        ".local/share/containers"
        ".local/share/direnv"
        ".local/share/keyrings"
        ".local/share/lxc"
        ".local/share/nvim"
        ".local/share/remmina"
        ".lmstudio"
        ".mitmproxy"
        ".mozilla"
        ".pki/nssdb"
        ".quickget"
        ".vscode"
        ".vscode-oss"
        "vms/disks"
        "vms/isos"
        "vms/nvrams"
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
      ];
      files = [
        ".ZAP/config.xml"
        ".aliases"
        ".config/nix/nix.conf"
        ".local/state/wireplumber/default-nodes"
        ".screenrc"
        ".zsh_history"
        ".zshrc"
      ];
    };
  };
}
