args@{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  sopsSecrets,
  ...
}:
let
  _ = builtins.trace "HOME.NIX got: ${lib.concatStringsSep ", " (builtins.attrNames args)}" null;
  unstablePkgs = import inputs.nixpkgs-unstable {
    config.allowUnfree = true;
  };
  stablePkgs = import inputs.nixpkgs-stable {
    config.allowUnfree = true;
  };
in
{
  home.activation.debugArgs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # this will log in journalctl -u home-manager-deadbeef.service -e

    echo "[+] Home Manager activation: showing specialArgs"
    echo "    -> ${lib.concatStringsSep " " (builtins.attrNames args)}"
  '';

  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
        ./i3/packages.nix
    ./rclone-wrapper/pentest-backup-and-remove-retired-pentests.nix
    ./rclone-wrapper/rclone-wrapper.nix

    ../01-general/pdf-reader/packages.nix
    ../01-general/pentesting/packages.nix
    ../01-general/windows-vms/quickemu-build-windows-10-and-11.nix

    inputs.sops-nix.homeManagerModules.sops
  ];
  sops = {
    defaultSopsFile = ../../secrets/l-werk-default-deadbeef.yaml;

    age = {
      sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      generateKey = true;
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
  home.enableNixpkgsReleaseCheck = false;
  home = {
    username = "deadbeef";
    homeDirectory = "/home/deadbeef";
  };
  gtk.enable = true;
  gtk.theme = {
    name = "Adwaita-dark";
    package = pkgs.gnome-themes-extra;
  };

  home.packages =
    let
      stable = with pkgs; [
        htop
        teams-for-linux
        intune-portal
        #microsoft-edge
        xdotool
        azure-cli
        i3status-rust
        discord
        obsidian
        google-chrome
        flameshot
        rofi
        remmina
        ffuf
        black 
        tmuxp

        # temp added files:
php84
php84Packages.composer
php84Packages.php-codesniffer
#php84Packages.php-cs-fixer

      ];
      unstable = with unstablePkgs; [
        vscode
        firefox
        exploitdb
        netexec
        certipy
        (burpsuite.override { proEdition = true; })
        gh
      ];
    in
    stable ++ unstable;

  programs.vscode = {
    enable = true;
    package = unstablePkgs.vscodium.fhs;
    mutableExtensionsDir = true;
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;
  # programs.git.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";

}
