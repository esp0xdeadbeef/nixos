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
    # inputs.hardware.nixosModules.common-cpu-intel
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix
    # Import your generated (nixos-generate-config) hardware configuration

    /*
        # testing router config, disable:
            ./containers/start_container.nix
      ./hardware/bootloader.nix
      ./hardware/boot-package.nix
      ./hardware/force-update.nix
      ./hardware/hardware-configuration.nix
      ./hardware/impermanence.nix
      ./hardware/lanzaboote.nix
      ./hardware/swap-and-tmpfs.nix

      ../01-general/desktop/applet-nm.nix
      ../01-general/desktop/fonts.nix
      ../01-general/desktop/packages.nix
      ../01-general/desktop/screen-recording.nix
      ../01-general/desktop/shell-env.nix
      ../01-general/desktop/users-and-groups.nix
      ../01-general/desktop/xdg-portal.nix
      ../01-general/enable-etc-hosts-editing/default.nix
      ../01-general/firmware-update/default.nix
      ../01-general/network/firewall.nix
      ../01-general/network/nat-lxc.nix
      ../01-general/network/nmcli.nix
      ../01-general/packages/1-general/archive-tools.nix
      ../01-general/packages/1-general/tooling.nix
      ../01-general/packages/data-tranformation/packages.nix
      ../01-general/packages/editors/packages.nix
      ../01-general/packages/encryption-and-password-management/packages.nix
      ../01-general/packages/git/packages.nix
      ../01-general/packages/network-troubleshooting/packages.nix
      ../01-general/packages/nix-specific/packages.nix
      ../01-general/packages/packages.nix
      ../01-general/packages/password-managers/1password.nix
      ../01-general/packages/terminals/packages.nix
      ../01-general/packages/terminals/terminal-optimisers/packages.nix
      ../01-general/packages/terminals/terminal-optimisers/updatedb.nix
      ../01-general/packages/window-managers/X-org/i3-wm/packages.nix
      ../01-general/packages/window-managers/X-org/packages.nix
      ../01-general/secrets/import-secrets.nix
      ../01-general/security/default.nix
      ../01-general/system/autoupdate.nix
      ../01-general/system/garbage-collection.nix
      ../01-general/system/locale.nix
      ../01-general/terminals/tmux/settings.nix
      ../01-general/time/timezone.nix
      ../01-general/virtualization-as-host/general.nix
      ../01-general/virtualization-as-host/libvirt.nix
      ../01-general/virtualization-as-host/lxc.nix
      ../01-general/virtualization-as-host/podman.nix
    */
    ../../01-general/system/garbage-collection.nix
    ../../01-general/time/timezone.nix

    ./hardware/bootloader.nix
    ./hardware/boot-package.nix
    ./hardware/force-update.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./hardware/lanzaboote.nix
    ./hardware/swap-and-tmpfs.nix
    #./hardware/network-onlymgmt.nix

    #./containers/start_containers.nix
    #../01-general/network/nmcli.nix
    ../../01-general/packages/1-general/tooling.nix
    #./containers/lan.nix

    ../../01-general/desktop/shell-env.nix
    ../../01-general/system/autoupdate.nix
    # it's a vm.. if you pwn the host you'll be able to login anyway.
    ../../99-testing/autologin.nix
    # ../02-window-manager-i3/environment.nix
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    #inputs.nixos-router.nixosModules
    #inputs.nixos-router.nixosModules.default

    #./containers/lan-v2.nix

    ./container-edge-pppoe-transit.nix
    #./isp-to-fake-isp.nix
  ];

  sops.defaultSopsFile = ../../../secrets/s-router-impermanence-root.yaml;
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };

  time.timeZone = "Europe/Amsterdam";

  programs.neovim.enable = true;
  programs.neovim.defaultEditor = true;

  environment.systemPackages = with pkgs; [
    ppp
    sops
    age
  ];

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

  networking.hostName = "s-router-core";

  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      # initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;

      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
        #"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqHQoNlgpqtFtwDfWXqnxk8+4BPS0nrOGQrlarOvneo deadbeef@l-esp"
      ];
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [ "wheel" ];
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

  boot.loader.systemd-boot.configurationLimit = 2;

  environment.interactiveShellInit = ''
    ZSH_THEME=pygmalion
    alias vim=nvim
  '';

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
