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
    # cd /home/deadbeef/github/nixos/nixos/l-werk ; ./generate-imports.sh

    ./1-custom-packages/azurehound/package.nix
    ./1-custom-packages/burp-fix.nix
    ./1-custom-packages/mxbuild/package.nix
    ./hardware/audio-and-bluetooth.nix
    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./hardware/nvidia.nix
    ./hardware/sound-fix.nix
    ./hardware/swap-and-tmpfs.nix
    ./llms/lmstudio.nix
    ./llms/ollama.nix
    ./lxc/bind-to-lxc.nix
    ./unmount-pentest-directory/unmount-hook.nix
    ./work-packages/wordlists/packages.nix
    ./work-packages/work/packages.nix

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
    ../01-general/packages/audio/packages.nix
    ../01-general/packages/browsers-mail-media-social-media/not-on-aarch64/packages.nix
    ../01-general/packages/browsers-mail-media-social-media/packages.nix
    ../01-general/packages/data-tranformation/packages.nix
    ../01-general/packages/editors/packages.nix
    ../01-general/packages/encryption-and-password-management/packages.nix
    ../01-general/packages/git/packages.nix
    ../01-general/packages/graphics/packages.nix
    ../01-general/packages/network-troubleshooting/packages.nix
    ../01-general/packages/nix-specific/packages.nix
    ../01-general/packages/packages.nix
    ../01-general/packages/password-managers/1password.nix
    ../01-general/packages/pdf/packages.nix
    ../01-general/packages/pentesting/packages.nix
    ../01-general/packages/rdp/packages.nix
    ../01-general/packages/scripting-languages/packages.nix
    ../01-general/packages/services/packages.nix
    ../01-general/packages/terminals/packages.nix
    ../01-general/packages/terminals/terminal-optimisers/packages.nix
    ../01-general/packages/terminals/terminal-optimisers/updatedb.nix
    ../01-general/packages/usb-tools/packages.nix
    ../01-general/packages/virtualization/packages.nix
    ../01-general/packages/window-managers/X-org/i3-wm/packages.nix
    ../01-general/packages/window-managers/X-org/packages.nix
    ../01-general/secrets/import-secrets.nix
    ../01-general/security/default.nix
    ../01-general/system/autoupdate.nix
    ../01-general/system/locale.nix
    ../01-general/terminals/tmux/settings.nix
    ../01-general/time/timezone.nix
    ../01-general/virtualization-as-host/general.nix
    ../01-general/virtualization-as-host/libvirt.nix
    ../01-general/virtualization-as-host/lxc.nix
    ../01-general/virtualization-as-host/podman.nix

    ../04-window-manager-other/environment.nix

    # ../99-testing/autologin-ssh-and-tty.nix
    # ../99-testing/autologin.nix

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];


  sops.defaultSopsFile = ../../secrets/l-werk-1-default.yaml;
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";



  
  programs.zsh.ohMyZsh.theme = "clean";


  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit inputs outputs;
    };
    users = {
      # Import your home-manager configuration
      deadbeef = import ../../home-manager/l-werk-1/home.nix;
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

  networking.hostName = "l-werk-1";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };
  # TODO: Configure your system-wide user settings (groups, etc), add more users as needed.
  users.users = {
    # FIXME: Replace with your username
    deadbeef = {
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      # initialPassword = " ";
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
