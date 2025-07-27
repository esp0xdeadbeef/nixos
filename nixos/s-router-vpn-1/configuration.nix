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
    # (cd /home/deadbeef/github/nixos/nixos/1-general ; find ../1-general | grep '\.nix$' | grep -v 'llms\|is-vm\|/packages.nix\|virtualization\|network\|darkmode\|applets\|autologin')
    ./hardware/hardware-configuration.nix
    ./network/configs_from_container.nix
    ./network/firewall.nix
    ./network/management-network.nix
    ./network/vlan-configuration-phys0.nix
    ./ssh-vim-and-basics.nix

    ../1-general/desktop/applets.nix
    ../1-general/desktop/environment.nix
    ../1-general/desktop/fonts.nix
    ../1-general/desktop/screen-recording.nix
    ../1-general/desktop/shell-env.nix
    ../1-general/desktop/users-and-groups.nix
    ../1-general/enable-etc-hosts-editing/default.nix
    ../1-general/hardware/is-vm/qemu-guest.nix
    ../1-general/packages/1-general/archive-tools.nix
    ../1-general/packages/1-general/tooling.nix
    ../1-general/packages/data-tranformation/packages.nix
    ../1-general/packages/editors/packages.nix
    ../1-general/packages/encryption-and-password-management/packages.nix
    ../1-general/packages/git/packages.nix
    ../1-general/packages/network-troubleshooting/packages.nix
    ../1-general/packages/packages.nix
    ../1-general/packages/terminals/packages.nix
    ../1-general/packages/terminals/terminal-optimisers/packages.nix
    ../1-general/packages/terminals/terminal-optimisers/updatedb.nix
    ../1-general/packages/window-managers/X-org/i3-wm/packages.nix
    ../1-general/packages/window-managers/X-org/packages.nix
    ../1-general/secrets/import-secrets.nix
    ../1-general/security/default.nix
    ../1-general/system/autologin.nix
    ../1-general/system/autoupdate.nix
    ../1-general/system/garbage-collection.nix
    ../1-general/system/locale.nix
    ../1-general/terminals/tmux/settings.nix
    ../1-general/time/timezone.nix
    

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

  networking.hostName = "s-router-vpn-1";

  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      initialPassword = " ";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg"
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

  # networking.hostName = "s-router-vpn-1";
  # services.openssh.enable = true;
  services.xserver.enable = true;
  # services.displayManager.sddm.enable = true;
  # services.desktopManager.plasma6.enable = true;
  boot.loader.grub.configurationLimit = 2;

  environment.interactiveShellInit = ''
    ZSH_THEME=agnoster
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
  system.stateVersion = "24.11";
}
