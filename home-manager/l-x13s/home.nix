{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    # ./steam/packages.nix
    ./configs/i3/packages.nix
    inputs.sops-nix.homeManagerModules.sops
  ];
  sops = {
    defaultSopsFile = ../../secrets/l-x13s-default.yaml;

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
    # hostPlatform = "aarch64-linux";
  };
  home.username = "deadbeef";
  home.homeDirectory = "/home/deadbeef";
  home.enableNixpkgsReleaseCheck = false;
  gtk.enable = true;
  gtk.theme = {
    name = "Adwaita-dark";
    package = pkgs.gnome-themes-extra;
  };

  home.packages = with pkgs; [
    htop
    xdotool
    azure-cli
    i3status-rust
    # discord
    obsidian
    vscode
    # google-chrome
    flameshot
    ffuf
    rofi
    remmina
    mitmproxy
    home-manager
  ];

  home.stateVersion = "24.11"; # Match your system state version
}
