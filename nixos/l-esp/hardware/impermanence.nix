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
    util-linux
    btrfs-progs
    coreutils
    findutils
  ];

  boot.initrd.systemd.services.rotateBtrfsRoot = {
    description = "Rotate /root Btrfs subvolume and prune >30 day snapshots";
    wantedBy = [ "initrd.target" ];
    after = [ "systemd-cryptsetup@crypted.service" ];
    before = [ "sysroot.mount" ];
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

      for i in $(find /btrfs_tmp/persist/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30); do
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

  # fileSystems."/var/lib/private" = {
  #   device = "/persist/var/lib/private";
  #   fsType = "none";
  #   options = [ "bind" ];
  # };

  # # 2) Make sure the source dir has the right perms
  # systemd.tmpfiles.rules = [
  #   "d /persist/var/lib/private 0700 root root -"
  # ];

  systemd.tmpfiles.rules = [
    "d /mnt/current_pentest 0755 root root -"
  ];
  environment.persistence."/persist" = {
    enable = true; # NB: Defaults to true, not needed
    hideMounts = true;
    directories = [
      "/root"
      # "/var/lib/ollama/models" # AI models
      # "/var/lib/ollama/.ollama" # AI ssh keys
      # "/var/lib/ollama"
      {
        # ls -la /var/lib/ollama # will output:
        # lrwxrwxrwx 1 root root 14  3 aug 05:06 /var/lib/ollama -> private/ollama
        directory = "/var/lib/private";
        mode = "0700";
      }
      {
        directory = "/var/lib/private/ollama";
        mode = "0700";
      }
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/sbctl"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      "/var/lib/libvirt" # libvirt configurations
      {
        directory = "/var/lib/colord";
        user = "colord";
        group = "colord";
        mode = "u=rwx,g=rx,o=";
      }
    ];
    files = [
      "/etc/machine-id"
      # "/var/cache/locatedb" # added it to persistent output in updatedb.nix (/persist/var/cache/locatedb); updatedb (locate <something>) history
      # {
      #   file = "/var/keys/secret_file";
      #   parentDirectory = {
      #     mode = "u=rwx,g=,o=";
      #   };
      # }
      # {
      #   file = "/var/cache/locatedb";
      #   parentDirectory = {
      #     mode = "u=rwx,g=rx,o=";
      #   };
      # }
      {
        file = "/var/cache/locatedb";
        parentDirectory = {
          # leave group/owner alone—just set mode
          mode = "u=rwx,g=rx,o=";
        };
      }
    ];
    users.deadbeef = {
      directories = [
        "github" # custom dir for my github projects

        "vms/isos"
        "vms/disks"
        "vms/nvrams"
        "pentest"
        "firefox-pentest-profile"

        #"Downloads"
        "Music"
        "Pictures"
        "Documents"
        "Videos"
        ".local/share/lxc"
        ".local/share/containers"
        ".local/share/nvim/" # neovim, i lazy load everything, configs of nix are not working.

        ".config/legcord" # (legcord -> armcord -> discord)
        ".config/libvirt/qemu" # libvirt qemu settings
        ".config/discord"
        ".config/spotify"
        ".config/autorandr" # autorandr profile
        ".config/google-chrome"
        ".config/chromium"
        ".config/sops"
        ".config/gh"
        ".config/qBittorrent" # qBittorrent settings
        ".config/obsidian" # Obsidian vault
        ".local/share/remmina" # remmina remote desktop connections
        ".config/Code" # vscode settings and data
        ".vscode" # workspace-specific settings and plugins
        ".config/VSCodium" # VSCodium settings and data
        ".vscode-oss" # VSCodium workspace-specific settings and plugins
        ".quickget" # quickget downloads
        ".continue" # quickget downloads

        ".dropbox"
        ".dropbox-dist"
        ".mitmproxy" # mitmproxy certificates
        ".mozilla" # firefox import certificates taking too long
        # ".local/state/wireplumber" # audio profiles

        ".config/slack" # Slack configuration
        ".config/zoom" # Zoom settings
        ".config/1Password" # 1Password

        # signal:
        ".config/Signal"
        ".config/maestral"

        # zap plugins:
        ".ZAP/plugin"
	
        # lm studio (backends, models etc.):
        ".lmstudio"

        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".ssh";
          mode = "0700";
        }
        {
          directory = ".local/share/keyrings";
          mode = "0700";
        }
        ".local/share/direnv"
      ];
      files = [
        ".local/state/wireplumber/default-nodes"
        ".screenrc"

        # zap (persist the config, which is containing the certificates):
        ".ZAP/config.xml"

        ".config/nix/nix.conf"
        ".zsh_history"
        ".zshrc"
        ".aliases"
      ];
    };
  };
}
