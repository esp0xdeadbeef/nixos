{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.impermanence;
  isWorkstationHost = lib.hasPrefix "l-" config.networking.hostName;

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

  getPkgName = pkg: pkg.pname or (lib.getName pkg);

  homePackages =
    lib.attrByPath
      [
        "home-manager"
        "users"
        cfg.primaryUser
        "home"
        "packages"
      ]
      [ ]
      config;

  installedPackageNames = map getPkgName (config.environment.systemPackages ++ homePackages);

  hasPackage = packageNames: lib.any (name: lib.elem name installedPackageNames) packageNames;

  hasLlmAgent = hasPackage [
    "claude-code"
    "claw-code"
    "codex"
    "crush"
    "forgecode"
    "gitclaw"
    "hermes-agent"
    "hermes-desktop"
    "hermes-hud"
    "mimo-code"
    "nanocoder"
    "oh-my-codex"
    "omp"
    "openclaw"
    "opencode"
    "openfang"
    "pi"
    "picoclaw"
    "qwen-code"
    "reasonix"
    "vessel-browser"
    "zeroclaw"
  ];

  hasDiscordClient = hasPackage [
    "discord"
    "discord-canary"
    "discord-ptb"
    "legcord"
    "vesktop"
    "webcord"
  ];

  desktopAppDirs =
    lib.optionals
      (hasPackage [
        "1password-gui"
        "1password"
      ])
      [
        ".config/1Password"
      ]
    ++ lib.optionals (hasPackage [ "vscode" ]) [
      ".config/Code"
      ".vscode"
    ]
    ++ lib.optionals (hasPackage [ "vscodium" ]) [
      ".config/VSCodium"
      ".vscode-oss"
    ]
    ++ lib.optionals (hasPackage [ "signal-desktop" ]) [
      ".config/Signal"
    ]
    ++ lib.optionals (hasPackage [ "chromium" ]) [
      ".config/chromium"
    ]
    ++ lib.optionals (hasPackage [ "google-chrome" ]) [
      ".config/google-chrome"
      ".pki/nssdb"
    ]
    ++
    lib.optionals
      (hasPackage [
        "dropbox"
        "maestral"
      ])
      [
        ".config/dropbox"
        ".config/maestral"
        ".dropbox"
        ".dropbox-dist"
      ]
    ++ lib.optionals (hasPackage [ "obsidian" ]) [
      ".config/obsidian"
    ]
    ++ lib.optionals (hasPackage [ "qbittorrent" ]) [
      ".config/qBittorrent"
    ]
    ++ lib.optionals (hasPackage [ "remmina" ]) [
      ".local/share/remmina"
      ".config/freerdp/server"
      ".config/remmina"
      ".cache/remmina"
    ]
    ++ lib.optionals (hasPackage [ "slack" ]) [
      ".config/slack"
    ]
    ++ lib.optionals (hasPackage [ "spotify" ]) [
      ".config/spotify"
    ]
    ++ lib.optionals (hasPackage [ "teams-for-linux" ]) [
      ".config/teams-for-linux"
    ]
    ++
    lib.optionals
      (hasPackage [
        "zoom-us"
        "zoom"
      ])
      [
        ".config/zoom"
      ]
    ++ lib.optionals (hasPackage [ "lmstudio" ]) [
      ".lmstudio"
    ]
    ++ lib.optionals (hasPackage [ "mitmproxy" ]) [
      ".mitmproxy"
    ]
    ++
    lib.optionals
      (hasPackage [
        "firefox"
        "librewolf"
        "zen"
        "zen-browser"
      ])
      [
        ".mozilla"
      ]
    ++ lib.optionals (hasPackage [ "quickemu" ]) [
      ".quickget"
    ];

  llmAgentDirs = [
    ".config/claude"
    ".config/codex"
    ".config/crush"
    ".config/hermes"
    ".config/mimo-code"
    ".config/nanocoder"
    ".config/opencode"
    ".config/qwen"
    ".config/qwen-code"
    ".config/reasonix"
    ".config/vessel-browser"
    ".cache/claude"
    ".cache/codex"
    ".cache/hermes"
    ".cache/opencode"
    ".cache/qwen"
    ".cache/qwen-code"
    ".claude"
    ".codex"
    ".gemini"
    ".opencode"
    ".qwen"
    ".local/share/claude"
    ".local/share/codex"
    ".local/share/hermes"
    ".local/share/opencode"
    ".local/share/qwen"
    ".local/share/qwen-code"
  ];

  discordClientDirs = [
    ".config/discord"
    ".config/Discord"
    ".config/discordcanary"
    ".config/discordptb"
    ".config/legcord"
    ".cache/discord"
    ".cache/Discord"
    ".local/share/discord"
    ".local/share/Discord"
  ];

  workstationUserDirs = [
    "pentest"
    "firefox-pentest-profile"
    "Documents"
    "Music"
    "Pictures"
    "Videos"
    ".BurpSuite"
    ".java/.userPrefs/burp"
    ".local/share/PrismLauncher"
    ".config/autorandr"
    ".config/kdeconnect"
    ".config/rclone"
    ".continue"
    ".ZAP/plugin"
  ];

  noCowUserDirs = lib.unique (
    (lib.optionals hasLlmAgent llmAgentDirs)
    ++ (lib.optionals hasDiscordClient discordClientDirs)
    ++ desktopAppDirs
  );

  noCowUserTmpfiles = lib.concatMap
    (
      dir:
      let
        path = "${cfg.persistPath}/home/${cfg.primaryUser}/${dir}";
      in
      [
        "d ${path} 0700 ${cfg.primaryUser} users -"
        "h ${path} - - - - +C"
      ]
    )
    noCowUserDirs;
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
      "d ${cfg.persistPath}/var/cache 0755 root root -"
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
    ++ noCowUserTmpfiles
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
          "vms"
          "vms/isos"
          "vms/disks"
          "vms/nvrams"
          ".local/share/lxc"
          ".local/share/containers"
          ".local/share/nvim"
          ".local/share/direnv"
          ".config/gh"
          ".config/libvirt/qemu"
          ".config/nix"
          ".config/sops"
          ".cache/nix-index"
        ]
        ++ lib.optionals isWorkstationHost workstationUserDirs
        ++ desktopAppDirs
        ++ lib.optionals hasLlmAgent llmAgentDirs
        ++ lib.optionals hasDiscordClient discordClientDirs
        ++ secureUserDirs
        ++ cfg.extraUserDirectories;

        files = [
          ".local/state/wireplumber/default-nodes"
          ".screenrc"
          ".ZAP/config.xml"
          ".zsh_history"
          ".zshrc"
          ".aliases"
        ]
        ++ lib.optionals (hasPackage [ "spotify-player" ]) [
          ".cache/spotify-player/credentials.json"
        ]
        ++ cfg.extraUserFiles;
      };
    };
  };
}
