# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, name
, outPath
, profiles
, ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example

    # Or modules from other flakes (such as nixos-hardware):
    inputs.hardware.nixosModules.common-cpu-intel
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    # Import your generated (nixos-generate-config) hardware configuration

    # Will test this box if relyable for router firmware hosting:
    inputs.lanzaboote.nixosModules.lanzaboote

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    # Bootstrap only: re-enable once secrets/s-tau-root.yaml exists.
    # inputs.sops-nix.nixosModules.sops

    profiles.nixos.core
    profiles.nixos.base.maintenance
    profiles.nixos.hardware.clock-sync
    profiles.nixos.laptop.xlayoutdisplay-hotplug
    profiles.nixos.nixpkgs.allow-unfree
    profiles.nixos.shell.zsh-prompt
    profiles.nixos.vm-host.nixos-shell
    "${outPath}/modules/nixos/local-users.nix"
    profiles.nixos.virtualization.libvirt
    profiles.nixos.virtualization.lxc
    profiles.nixos.virtualization.podman

    # autologin for this vm
    #../../99-testing
    "${outPath}/library/99-testing/enable-ssh-with-authorized-keys-and-add-NOPASSWD.nix"

    # local nix files:
    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    # Depends on SOPS-backed NAS secrets, so keep it disabled during bootstrap.
    # ./connect-nas
  ];

  # Bootstrap only. This is the yescrypt hash for the temporary password
  # "nixos"; replace it with sops-nix after the real tau host key exists.
  users.users.deadbeef.hashedPassword = "$y$j9T$Ml1U6HvkeXcm6IKcJcNtd/$8/IQEIMfWjTZ.B5tJF.oepeVrOjppKfkpRpybaaSZL2";

  boot.swraid = {
    # Disko creates the LUKS container on this mdraid array; the initrd must
    # assemble it before cryptsetup can find the root device UUID.
    enable = true;
    mdadmConf = ''
      ARRAY /dev/md/root metadata=1.2 UUID=82520a72:9a366735:99afae75:870b517f
      PROGRAM ${pkgs.coreutils}/bin/true
    '';
  };

  # Keep the same VM declarations as s-sigma, but do not start them on tau
  # until the active/standby router plan is explicit.
  local.vmHost.nixosShell.autoStart = false;

  # Re-enable once secrets/s-tau-root.yaml exists and is encrypted to tau.
  # sops.defaultSopsFile = "${outPath}/secrets/${name}-root.yaml";
  # sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  #
  # sops.secrets."deadbeef-passwd" = {
  #   neededForUsers = true;
  # };

  time.timeZone = "Europe/Amsterdam";

  services.xserver = {
    enable = true;
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3lock
        i3status
      ];
    };
    xkb.layout = "us";
  };
  services.displayManager.defaultSession = "none+i3";
  services.displayManager.gdm.enable = true;
  security.pam.services.i3lock.enable = true;
  local.laptop.xlayoutdisplayHotplug.configLines = [
    "dpi=96"
  ];
  local.laptop.xlayoutdisplayHotplug.maxResolution = "1680x1050";

  home-manager = {
    sharedModules = [
      # Bootstrap only: re-enable once secrets/s-tau-root.yaml exists.
      # inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit inputs outputs profiles;
      inherit outPath;
      hostName = name;
    };
    users = {
      deadbeef = import "${outPath}/home-manager/${name}/home.nix";
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
    # specify that it is aarch64-linux:
    hostPlatform = "x86_64-linux";
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

  networking.hostName = name;

  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      # initialPassword = " ";
      # hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;

      isNormalUser = true;
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
    };
  };

  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  services.openssh = {
    enable = true;
    settings = {
      # Opinionated: forbid root login through SSH.
      PermitRootLogin = "no";
      # Opinionated: use keys only.
      # Remove if you want to SSH using passwords
      PasswordAuthentication = true;
    };
  };

  boot.loader.systemd-boot.configurationLimit = 12;

  local.shell.zshPrompt.enable = true;

  environment.systemPackages = [
    pkgs.ethtool
  ];

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
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
