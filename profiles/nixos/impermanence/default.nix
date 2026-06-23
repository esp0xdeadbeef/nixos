{
  config,
  lib,
  pkgs,
  ...
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

  normalUserNames = lib.filter (
    name: name != "root" && (config.users.users.${name}.isNormalUser or false)
  ) (lib.attrNames config.users.users);

  userGroup = user: config.users.users.${user}.group or "users";

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

  hasBurp = hasPackage [
    "burpsuite"
    "burp"
  ];

  hasZap = hasPackage [
    "zap"
    "zaproxy"
  ];

  hasContinue = hasPackage [
    "vscode-extension-Continue-continue"
    "vscode-extension-continue-continue"
    "continue"
  ];

  hasVirtualMachines =
    (config.virtualisation.libvirtd.enable or false)
    || hasPackage [
      "virt-manager"
      "quickemu"
    ];

  hasLxc =
    (config.virtualisation.lxc.enable or false)
    || (config.virtualisation.incus.enable or false)
    || hasPackage [
      "lxc"
      "incus"
    ];

  hasContainerState =
    hasLxc
    || (config.virtualisation.podman.enable or false)
    || (config.virtualisation.docker.enable or false);

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
          "maestral-gui"
          "maestral-qt"
        ])
        [
          ".config/dropbox"
          ".config/maestral"
          ".local/share/maestral"
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
    ++ lib.optionals (hasPackage [ "spotify-player" ]) [
      ".config/spotify-player"
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

  containerStateDirs = lib.optionals hasContainerState [
    ".local/share/containers"
  ];

  workstationUserDirs = [
    "pentest"
    "firefox-pentest-profile"
    "Documents"
    "Music"
    "Pictures"
    "Videos"
    ".local/share/PrismLauncher"
    ".config/autorandr"
    ".config/kdeconnect"
    ".config/rclone"
  ]
  ++ lib.optionals hasContinue [
    ".continue"
  ]
  ++ lib.optionals hasBurp [
    ".BurpSuite"
    ".java/.userPrefs/burp"
  ]
  ++ lib.optionals hasZap [
    ".ZAP/plugin"
  ];

  noCowUserDirs = lib.unique (
    (lib.optionals hasLlmAgent llmAgentDirs)
    ++ (lib.optionals hasDiscordClient discordClientDirs)
    ++ containerStateDirs
    ++ desktopAppDirs
  );

  spotifyPlayerFiles = lib.optionals (hasPackage [ "spotify-player" ]) [
    ".cache/spotify-player/credentials.json"
    ".cache/spotify-player/user_client_token.json"
  ];

  spotifyPlayerTmpfiles = lib.optionals (hasPackage [ "spotify-player" ]) (
    lib.concatMap (
      user:
      let
        group = userGroup user;
      in
      [
        "d /home/${user}/.cache/spotify-player 0700 ${user} ${group} -"
        "d ${cfg.persistPath}/home/${user}/.cache/spotify-player 0700 ${user} ${group} -"
      ]
    ) normalUserNames
  );

  generatedSshEtcEntries = lib.filterAttrs (
    name: entry: lib.hasPrefix "ssh/" name && (entry ? source)
  ) config.environment.etc;

  generatedSshEtcTmpfiles =
    [
      "d ${cfg.persistPath}/etc/ssh/authorized_keys.d 0755 root root -"
    ]
    ++ lib.mapAttrsToList (
      name: entry:
      if lib.hasPrefix "ssh/authorized_keys.d/" name then
        "C+ ${cfg.persistPath}/etc/${name} 0644 root root - ${entry.source}"
      else
        "L+ ${cfg.persistPath}/etc/${name} - - - - ${entry.source}"
    ) generatedSshEtcEntries;

  sharedUserDirectories = [
    "github"
    ".local/share/nvim"
    ".local/share/direnv"
    ".config/gh"
    ".config/nix"
    ".config/sops"
    ".cache/nix-index"
  ]
  ++ lib.optionals hasVirtualMachines [
    "vms"
    "vms/isos"
    "vms/disks"
    "vms/nvrams"
    ".config/libvirt/qemu"
  ]
  ++ lib.optionals hasLxc [
    ".local/share/lxc"
  ]
  ++ containerStateDirs
  ++ lib.optionals isWorkstationHost workstationUserDirs
  ++ desktopAppDirs
  ++ lib.optionals hasLlmAgent llmAgentDirs
  ++ lib.optionals hasDiscordClient discordClientDirs
  ++ secureUserDirs
  ++ cfg.extraUserDirectories;

  sharedUserFiles = [
    ".local/state/wireplumber/default-nodes"
    ".screenrc"
    ".zsh_history"
    ".zshrc"
    ".aliases"
  ]
  ++ lib.optionals hasZap [
    ".ZAP/config.xml"
  ]
  ++ spotifyPlayerFiles
  ++ cfg.extraUserFiles;

  sharedUserPersistence = lib.genAttrs normalUserNames (_user: {
    directories = sharedUserDirectories;
    files = sharedUserFiles;
  });

  sharedUserTmpfiles = lib.concatMap (
    user:
    let
      group = userGroup user;
    in
    [
      "d /home/${user}/.cache 0755 ${user} ${group} -"
      "d ${cfg.persistPath}/home/${user}/.cache 0755 ${user} ${group} -"
      "d /home/${user}/.cache/nix-index 0755 ${user} ${group} -"
      "d ${cfg.persistPath}/home/${user}/.cache/nix-index 0755 ${user} ${group} -"
    ]
    ++ lib.optionals hasVirtualMachines [
      "d ${cfg.persistPath}/home/${user}/vms/disks 0755 ${user} ${group} -"
      "h ${cfg.persistPath}/home/${user}/vms/disks - - - - +C"
    ]
    ++ lib.optionals hasLxc [
      "d ${cfg.persistPath}/home/${user}/.local/share/lxc 0755 ${user} ${group} -"
      "h ${cfg.persistPath}/home/${user}/.local/share/lxc - - - - +C"
    ]
  ) normalUserNames;

  noCowUserTmpfiles = lib.concatMap (
    user:
    lib.concatMap (
      dir:
      let
        path = "${cfg.persistPath}/home/${user}/${dir}";
        group = userGroup user;
      in
      [
        "d ${path} 0700 ${user} ${group} -"
        "h ${path} - - - - +C"
      ]
    ) noCowUserDirs
  ) normalUserNames;
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
      after = [
        "systemd-cryptsetup@${cfg.rootMapperName}.service"
        "systemd-hibernate-resume.service"
      ];
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

    programs.fuse.userAllowOther = true;
    environment.systemPackages = with pkgs; [ btrfs-progs ];

    systemd.services.sshd-keygen = lib.mkIf config.services.openssh.enable {
      requires = [ "etc-ssh.mount" ];
      after = [ "etc-ssh.mount" ];
    };

    systemd.services.sshd = lib.mkIf config.services.openssh.enable {
      requires = [ "etc-ssh.mount" ];
      after = [ "etc-ssh.mount" ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.persistPath}/etc 0755 root root -"
      "d ${cfg.persistPath}/etc/ssh 0755 root root -"
      "d ${cfg.persistPath}/var/cache 0755 root root -"
      "d /mnt/current_pentest 0755 root root -"
      "d ${cfg.persistPath}/var/lib/libvirt/images 0711 root root -"
      "h ${cfg.persistPath}/var/lib/libvirt/images - - - - +C"
    ]
    ++ sharedUserTmpfiles
    ++ spotifyPlayerTmpfiles
    ++ noCowUserTmpfiles
    ++ generatedSshEtcTmpfiles
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
        "/var/lib/systemd/timers"
        "/etc/ssh"
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

      users = sharedUserPersistence;
    };
  };
}
