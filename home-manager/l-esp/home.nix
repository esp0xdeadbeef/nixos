{ inputs
, outputs
, lib
, config
, pkgs
, outPath
, profiles
, primaryUser
, primaryUserHome
, ...
}:
let
  unstablePkgs = pkgs.unstable;
in
{
  imports = [
    ./configs/dropbox/packages.nix
    ./configs/flameshot/packages.nix
    ./configs/git/config.nix
    ./configs/nixpkgs-allowunfree/packages.nix
    ./configs/tmuxp/packages.nix
    ./projects
    profiles.home-manager.desktop.legcord
    profiles.home-manager.desktop-i3

    # update nix-index database
    inputs.nix-index-database.homeModules.nix-index

    # zen browser:
    # inputs.zen-browser.homeModules.beta
    # or inputs.zen-browser.homeModules.twilight
    # or inputs.zen-browser.homeModules.twilight-official

    ./configs/minecraft
  ];

  # programs.zen-browser.enable = true;

  sops = {
    defaultSopsFile = "${outPath}/secrets/l-esp-default-${primaryUser}.yaml";
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
    username = primaryUser;
    homeDirectory = primaryUserHome;
  };

  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";

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
        distrobox
        xlayoutdisplay
      ];

      unstable = with unstablePkgs; [
        # firefox
        gh
      ];
    in
    stable ++ unstable;

  local.desktop.legcord.enable = true;

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";
}
