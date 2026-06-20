{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.impermanence;

  persistenceType = lib.types.listOf lib.types.anything;

  locatedbFile = {
    file = "/var/cache/locatedb";
    parentDirectory.mode = "u=rwx,g=rx,o=";
  };

  privateDir = {
    directory = "/var/lib/private";
    mode = "0700";
  };

  rootHomeDir = {
    directory = "/root";
    mode = "0700";
  };

  ollamaPrivateDir = {
    directory = "/var/lib/private/ollama";
    mode = "0700";
  };

  colordDir = mode: {
    directory = "/var/lib/colord";
    user = "colord";
    group = "colord";
    inherit mode;
  };

  secureUserDirs = [
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
  ];
in
{
  options.local.impermanence = {
    enable = lib.mkEnableOption "shared impermanence defaults";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Persistent root used by impermanence.";
    };

    primaryUser = lib.mkOption {
      type = lib.types.str;
      default = "deadbeef";
      description = "Interactive user whose home state is persisted.";
    };

    rootMapperName = lib.mkOption {
      type = lib.types.str;
      default = "crypted";
      description = "Mapped LUKS device that contains the btrfs root subvolumes.";
    };

    rotateBtrfsRoot.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Rotate the ephemeral btrfs /root subvolume during initrd.";
    };

    persistSshHostKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Store OpenSSH host keys under the persistent root.";
    };

    colordMode = lib.mkOption {
      type = lib.types.str;
      default = "u=rwx,g=rx,o=";
      description = "Mode for the persisted colord state directory.";
    };

    extraTmpfiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional tmpfiles rules for persistent paths.";
    };

    extraSystemDirectories = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional system directories persisted under persistPath.";
    };

    extraSystemFiles = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional system files persisted under persistPath.";
    };

    extraUserDirectories = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional primary-user directories persisted under persistPath.";
    };

    extraUserFiles = lib.mkOption {
      type = persistenceType;
      default = [ ];
      description = "Additional primary-user files persisted under persistPath.";
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${cfg.persistPath}.neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;

    boot.initrd.systemd.enable = true;

    boot.initrd.systemd.initrdBin = with pkgs; [
      bash
      btrfs-progs
      coreutils
      findutils
      util-linux
    ];

    boot.initrd.systemd.services.rotateBtrfsRoot = lib.mkIf cfg.rotateBtrfsRoot.enable {
      description = "Rotate /root Btrfs subvolume and prune old roots";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-cryptsetup@${cfg.rootMapperName}.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      script = ''
        #!${pkgs.bash}/bin/bash -euo pipefail

        mkdir /btrfs_tmp
        mount /dev/mapper/${cfg.rootMapperName} /btrfs_tmp

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

            while read -r i; do
                delete_subvolume_recursively "/btrfs_tmp/persist/old_roots/$i"
            done < <(find /btrfs_tmp/persist/old_roots/ -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -r | tail -n +31)
        fi

        btrfs subvolume create /btrfs_tmp/root
        umount /btrfs_tmp
      '';
    };

    services.openssh.hostKeys = lib.mkIf cfg.persistSshHostKeys [
      {
        type = "ed25519";
        path = "${cfg.persistPath}/etc/ssh/ssh_host_ed25519_key";
      }
      {
        type = "rsa";
        bits = 4096;
        path = "${cfg.persistPath}/etc/ssh/ssh_host_rsa_key";
      }
    ];

    programs.fuse.userAllowOther = true;
    environment.systemPackages = with pkgs; [ btrfs-progs ];

    systemd.tmpfiles.rules = [
      "d ${cfg.persistPath}/etc 0755 root root -"
      "d ${cfg.persistPath}/etc/ssh 0755 root root -"
      "d /mnt/current_pentest 0755 root root -"
      "d ${cfg.persistPath}/var/lib/libvirt/images 0711 root root -"
      "h ${cfg.persistPath}/var/lib/libvirt/images - - - - +C"
      "d ${cfg.persistPath}/home/${cfg.primaryUser}/vms/disks 0755 ${cfg.primaryUser} users -"
      "h ${cfg.persistPath}/home/${cfg.primaryUser}/vms/disks - - - - +C"
      "d /home/${cfg.primaryUser}/.cache 0755 ${cfg.primaryUser} users -"
      "d ${cfg.persistPath}/home/${cfg.primaryUser}/.cache 0755 ${cfg.primaryUser} users -"
      "d /home/${cfg.primaryUser}/.cache/nix-index 0755 ${cfg.primaryUser} users -"
      "d ${cfg.persistPath}/home/${cfg.primaryUser}/.cache/nix-index 0755 ${cfg.primaryUser} users -"
      "d ${cfg.persistPath}/home/${cfg.primaryUser}/.local/share/lxc 0755 ${cfg.primaryUser} users -"
      "h ${cfg.persistPath}/home/${cfg.primaryUser}/.local/share/lxc - - - - +C"
      "d ${cfg.persistPath}/home/${cfg.primaryUser}/.local/share/containers 0700 ${cfg.primaryUser} users -"
      "h ${cfg.persistPath}/home/${cfg.primaryUser}/.local/share/containers - - - - +C"
    ]
    ++ cfg.extraTmpfiles;

    environment.persistence.${cfg.persistPath} = {
      enable = true;
      hideMounts = true;

      directories = [
        rootHomeDir
        privateDir
        ollamaPrivateDir
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/sbctl"
        "/var/lib/systemd/coredump"
        "/etc/NetworkManager/system-connections"
        "/var/lib/libvirt"
        (colordDir cfg.colordMode)
      ]
      ++ cfg.extraSystemDirectories;

      files = [
        "/etc/machine-id"
        locatedbFile
      ]
      ++ cfg.extraSystemFiles;

      users.${cfg.primaryUser} = {
        directories = [
          "github"
          "pentest"
          "firefox-pentest-profile"
          "Documents"
          "Music"
          "Pictures"
          "Videos"
          "vms"
          "vms/isos"
          "vms/disks"
          "vms/nvrams"
          ".BurpSuite"
          ".java/.userPrefs/burp"
          ".local/share/PrismLauncher"
          ".local/share/lxc"
          ".local/share/containers"
          ".local/share/nvim"
          ".local/share/remmina"
          ".local/share/direnv"
          ".config/1Password"
          ".config/Code"
          ".config/Signal"
          ".config/VSCodium"
          ".config/autorandr"
          ".config/chromium"
          ".config/discord"
          ".config/dropbox"
          ".config/freerdp/server"
          ".config/gh"
          ".config/google-chrome"
          ".config/kdeconnect"
          ".config/legcord"
          ".config/libvirt/qemu"
          ".config/maestral"
          ".config/nix"
          ".config/obsidian"
          ".config/qBittorrent"
          ".config/rclone"
          ".config/remmina"
          ".config/slack"
          ".config/sops"
          ".config/spotify"
          ".config/teams-for-linux"
          ".config/zoom"
          ".dropbox"
          ".dropbox-dist"
          ".cache/nix-index"
          ".cache/remmina"
          ".continue"
          ".lmstudio"
          ".mitmproxy"
          ".mozilla"
          ".pki/nssdb"
          ".quickget"
          ".vscode"
          ".vscode-oss"
          ".ZAP/plugin"
        ]
        ++ secureUserDirs
        ++ cfg.extraUserDirectories;

        files = [
          ".local/state/wireplumber/default-nodes"
          ".screenrc"
          ".ZAP/config.xml"
          ".config/nix/nix.conf"
          ".zsh_history"
          ".zshrc"
          ".aliases"
        ]
        ++ cfg.extraUserFiles;
      };
    };
  };
}
