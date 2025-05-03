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
    ./hardware/hardware-configuration.nix

    ../1-general/1-custom-packages/azurehound/package.nix
    ../1-general/1-custom-packages/mxbuild/package.nix
    ../1-general/desktop/applets.nix
    ../1-general/desktop/darkmode.nix
    ../1-general/desktop/environment.nix
    ../1-general/desktop/fonts.nix
    ../1-general/desktop/screen-recording.nix
    ../1-general/desktop/shell-env.nix
    ../1-general/desktop/users-and-groups.nix
    ../1-general/enable-etc-hosts-editing/default.nix
    ../1-general/hardware/is-vm/qemu-guest.nix
    ../1-general/llms/lmstudio.nix
    ../1-general/llms/ollama.nix
    ../1-general/network/firewall.nix
    ../1-general/network/nat-lxc.nix
    ../1-general/network/nmcli.nix
    ../1-general/packages/1-general/tooling.nix
    ../1-general/packages/audio/packages.nix
    ../1-general/packages/browsers-mail-media-social-media/not-on-aarch64/packages.nix
    ../1-general/packages/browsers-mail-media-social-media/packages.nix
    ../1-general/packages/browsers-mail-media-social-media/work/packages.nix
    ../1-general/packages/data-tranformation/packages.nix
    ../1-general/packages/editors/packages.nix
    ../1-general/packages/encryption-and-password-management/packages.nix
    ../1-general/packages/git/packages.nix
    ../1-general/packages/graphics/packages.nix
    ../1-general/packages/network-troubleshooting/packages.nix
    ../1-general/packages/nix-specific/packages.nix
    ../1-general/packages/packages.nix
    ../1-general/packages/pdf/packages.nix
    ../1-general/packages/pentesting/packages.nix
    ../1-general/packages/pentesting/work/packages.nix
    ../1-general/packages/rdp/packages.nix
    ../1-general/packages/scripting-languages/packages.nix
    ../1-general/packages/services/packages.nix
    ../1-general/packages/terminals/packages.nix
    ../1-general/packages/terminals/terminal-optimisers/packages.nix
    ../1-general/packages/terminals/terminal-optimisers/updatedb.nix
    ../1-general/packages/usb-tools/packages.nix
    ../1-general/packages/virtualization/packages.nix
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
    ../1-general/virtualization/general.nix
    ../1-general/virtualization/libvirt.nix
    ../1-general/virtualization/lxc.nix
    ../1-general/virtualization/podman.nix
    {
      environment.interactiveShellInit = ''
        ZSH_THEME=random
      '';
    }
    # (import "${inputs.home-manager}")
    # {inputs.home-manager.users.deadbeef = import ./home-manager/l-werk/home.nix;}
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users = {
      # Import your home-manager configuration
      deadbeef = import ../../home-manager/s-test-vm/home.nix;
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

      # widevine patch:
      # inputs.nixos-aarch64-widevine.overlays.default

    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
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
  networking.hostName = "l-x13s";
  networking.networkmanager.enable = true;

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
      # PermitRootLogin = "no";
      # Opinionated: use keys only.
      # Remove if you want to SSH using passwords
      PasswordAuthentication = true;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.11";
}
