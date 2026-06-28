# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, ...
}:
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    ./i3.nix
    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
  ];
  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.legcord-unstable-overwrite

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

  home.packages = with pkgs; [
    htop
    # teams-for-linux
    #intune-portal
    # microsoft-edge
    xdotool
    # azure-cli
    i3status-rust
    # discord
    # obsidian
    vscode
    google-chrome
    flameshot
    rofi
    # remmina
    mitmproxy
    # netexec
    ffuf
    #exploitdb
    inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.exploitdb
    # (inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.burpsuite.override { iconName = "pro"; })
  ];
  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";

}
