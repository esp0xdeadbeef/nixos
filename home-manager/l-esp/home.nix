# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  sopsSecrets,
  ...
}:
let
  unstablePkgs = import inputs.nixpkgs-unstable {
    # system = "x86_64-linux";
    config.allowUnfree = true;
  };
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./configs/dropbox/packages.nix
    ./configs/steam/packages.nix
    ./configs/i3/packages.nix
    ./configs/i3status-rust/packages.nix
  ];
  sops = {
    defaultSopsFile = ../../secrets/l-esp-default-deadbeef.yaml;

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
      xdotool
      i3status-rust
      obsidian
      google-chrome
      flameshot
      rofi
      remmina
      legcord
      ffuf
    ];
    unstable = with unstablePkgs; [
      vscode
      firefox
      exploitdb
      netexec
    ];
  in
    stable ++ unstable;


  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";

}
