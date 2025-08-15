# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example

    # Or modules from other flakes (such as nixos-hardware):
    inputs.hardware.nixosModules.common-cpu-intel
    # inputs.hardware.nixosModules.common-gpu-nvidia

    # You can also split up your configuration and import pieces of it here:
    # cd /home/deadbeef/github/nixos/nixos/l-esp ; ./generate-imports.sh

STRING_TO_REPLACE_WITH_GENERATE_IMPORT.SH

    ../02-window-manager-i3/environment.nix
    ../30-physical-hardware-connections/why2025-badge/default.nix
    # ../99-testing/autologin-ssh-and-tty.nix
  

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p16s-intel-gen2


    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];

  hardware.nvidia.prime = {
    intelBusId = "PCI:00:02:0";
    nvidiaBusId = "PCI:01:00:0";
  };

  sops.defaultSopsFile = ../../secrets/l-esp-default.yaml;
  # This will automatically import SSH keys as age keys
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  # This is using an age key that is expected to already be in the filesystem
  # sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  # This will generate a new key if the key specified above does not exist
  # sops.age.generateKey = true;
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";
  # This is the actual specification of the secrets.
  # sops.secrets.example-key = { };
  # sops.secrets."myservice/my_subdir/my_secret" = { };

  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    users = {
      # Import your home-manager configuration
      deadbeef = import ../../home-manager/l-esp/home.nix;
    };
  };

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        # Enable flakes and new 'nix' command
        experimental-features = "nix-command flakes";
        # Opinionated: disable global registry
        flake-registry = "";
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };
      # Opinionated: disable channels
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  # FIXME: Add the rest of your current configuration

  # networking.hostName = "l-werk";
  # networking.networkmanager.enable = true;
  # time.timeZone = "Europe/Amsterdam";

  networking.hostName = "l-esp";
  networking.networkmanager.enable = true;
  # unlock gnome shit at unlock:
  security.pam.services.login.enableGnomeKeyring = true;
  environment.interactiveShellInit = ''
    ZSH_THEME=robbyrussell
  '';

  ## moved this to home-manager/l-esp/dropbox/packages.nix
  # systemd.user.services.dropbox = {
  #   description = "Dropbox service";
  #   wantedBy = [ "default.target" ];
  #   after = [ "network-online.target" ];
  #   serviceConfig = {
  #     ExecStart = "${pkgs.dropbox}/bin/dropbox";
  #     Restart = "on-failure";
  #   };
  # };
  # secrets.deadbeef-passwd.neededForUsers = true;
  # sops = {
  #   secrets.deadbeef-passwd = {
  #     neededForUsers = true;
  #   };
  # };
  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };
  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      # TODO: You can ss-test-vmet an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!


      # initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;

      
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
        # "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
      ];
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [ "wheel" ];
    };
  };

  environment = {
    systemPackages = [
      (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
        qemu-system-x86_64 \
          -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
          "$@"
      '')
    ];
  };

  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  # services.openssh = {
  #   enable = false;
  #   settings = {
  #     # Opinionated: forbid root login through SSH.
  #     PermitRootLogin = "no";
  #     # Opinionated: use keys only.
  #     # Remove if you want to SSH using passwords
  #     PasswordAuthentication = true;
  #   };
  # };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.11";
}
