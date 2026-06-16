{ inputs
, outputs
, lib
, config
, pkgs
, name
, outPath
, modulesPath
, ...
}:

let
  codexUser = "deadbeef";
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"

    ./codex
    ./disko.nix
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  swapDevices = [
    {
      device = "/persist/var/lib/swapfile";
      size = 45 * 1024;
    }
  ];

  networking.hostName = "codex-jail";

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];

    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = "nix-command flakes";
        flake-registry = "";
        max-jobs = "auto";
        cores = 0;
        nix-path = config.nix.nixPath;
      };

      channel.enable = false;

      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  boot.loader.grub.enable = lib.mkForce true;
  boot.loader.grub.efiSupport = lib.mkForce false;
  boot.loader.grub.device = lib.mkForce "nodev";
  boot.loader.grub.devices = lib.mkForce [ ];
  boot.loader.grub.mirroredBoots = lib.mkForce [
    {
      devices = [ "/dev/vda" ];
      path = "/boot";
    }
  ];
  boot.loader.grub.useOSProber = lib.mkForce false;

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];
  time.timeZone = "Europe/Amsterdam";

  fileSystems."/boot".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  systemd.tmpfiles.rules = [
    "d /persist/etc 0755 root root -"
    "d /persist/etc/ssh 0755 root root -"
  ];

  sops = {
    defaultSopsFile = "${outPath}/secrets/${name}.yaml";

    age.sshKeyPaths = [
      "/persist/etc/ssh/ssh_host_ed25519_key"
    ];

    secrets = {
      deadbeef-passwd = {
        neededForUsers = true;
      };

      gh-token = {
        owner = codexUser;
        group = "users";
        mode = "0600";
        path = "/run/secrets/gh-token";
      };

      hetzner-token = {
        owner = codexUser;
        group = "users";
        mode = "0600";
        path = "/run/secrets/hetzner-token";
      };
    };
  };
  users.users = {
    root = {
      hashedPassword = "!";
    };

    deadbeef = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      extraGroups = [ "wheel" ];

      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA1Rmk/3OrwWB5qvWrltIDGgK2vxQIXfRtPkAg56gHB1 deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3aMs0pSWWYY3Sah8zYP0cJKW7SO/5F8Z7QjM359C+i root@nixos"
      ];

      shell = pkgs.zsh;
    };
  };

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        bits = 4096;
        type = "rsa";
      }
    ];

    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
  };

  services.getty.autologinUser = lib.mkForce "deadbeef";
  services.displayManager.autoLogin.enable = lib.mkForce false;

  security.sudo.enable = true;
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    tmux
    tmuxp
    sops
    curl
    wget
    jq
    gron
    ripgrep
    fd
    htop
    btop
    pciutils
    usbutils
    iproute2
    iputils
    bind
    nmap
    tcpdump
    traceroute
    mtr
    netcat-openbsd
    socat
    nftables
    conntrack-tools
    ethtool
    iptables
    procps
    lsof
    file
    tree
    unzip
    zip
    rsync
    moreutils
    nixpkgs-fmt
    nil
    statix
    deadnix
    shellcheck
    gcc
    gdb
    gnumake
    pkg-config
    python3
    ruff
    nodejs
    gh
  ];

  programs.zsh.enable = true;

  #environment.interactiveShellInit = ''
  #  ZSH_THEME=agnoster
  #  sudo cat /run/secrets/gh-token | gh auth login --with-token
  #  gh auth setup-git
  #'';
  environment.interactiveShellInit = ''
    ZSH_THEME=agnoster

    if [ -r /run/secrets/gh-token ]; then
      export GH_TOKEN="$(cat /run/secrets/gh-token)"
      export GITHUB_TOKEN="$GH_TOKEN"

      git config --global credential.https://github.com.helper '!gh auth git-credential' >/dev/null 2>&1 || true
      git config --global credential.https://gist.github.com.helper '!gh auth git-credential' >/dev/null 2>&1 || true
    fi
  '';

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${codexUser} = {
    programs.zsh = {
      enable = true;
    };

    home.stateVersion = "26.05";
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log"
      "/home/deadbeef"
      "/root"
    ];

    files = [
      "/etc/machine-id"
    ];
  };

  system.stateVersion = "25.11";
}
