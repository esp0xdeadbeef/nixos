{ inputs
, outputs
, lib
, config
, pkgs
, outPath
, profiles
, ...
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
    profiles.home-manager.desktop.legcord
    profiles.home-manager.desktop-i3
    profiles.home-manager.mail.aerc
    profiles.home-manager.mail.geary
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
    # hostPlatform = "aarch64-linux";
  };
  home.username = "deadbeef";
  home.homeDirectory = "/home/deadbeef";
  home.enableNixpkgsReleaseCheck = false;
  sops.defaultSopsFile = "${outPath}/secrets/l-portal-default.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "chromium-browser.desktop" ];
      "application/pdf" = [ "okularApplication_pdf.desktop" ];
      "x-scheme-handler/http" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/https" = [ "chromium-browser.desktop" ];
      "x-scheme-handler/about" = [ "chromium-browser.desktop" ];
    };
  };

  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.i3.statusRust.battery.enable = true;
  local.desktop.legcord.enable = true;

  home.packages = with pkgs; [
    htop
    azure-cli
    # discord
    obsidian
    # google-chrome
    chromium
    flameshot
    remmina
    spotify-player
    home-manager
  ];

  home.stateVersion = "26.05"; # Match your system state version
}
