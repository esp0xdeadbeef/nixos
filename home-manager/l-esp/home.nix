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
  unstablePkgs = pkgs.unstable;
  stablePkgs = import inputs.nixpkgs-stable {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };
in
{
  home.activation.debugArgs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # this will log in journalctl -u home-manager-deadbeef.service -e
    echo "[+] Home Manager activation: showing specialArgs"
    echo " -> ${lib.concatStringsSep " " (builtins.attrNames args)}"
  '';

  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./configs/dropbox/packages.nix
    ./configs/flameshot/packages.nix
    ./configs/git/config.nix
    ./configs/nixpkgs-allowunfree/packages.nix
    ./configs/sway/packages.nix
    ./configs/tmuxp/packages.nix
    #./projects/osee/create-x2go-profile.nix
    #./projects/osee/start-lxc.nix
    #./projects/osee/vm-settings-resize-guest.nix
    ../01-general/darkmode/config.nix
    ../01-general/editors/vscode.nix
    ../01-general/pdf-reader/packages.nix
    ../01-general/pentesting/packages.nix
    ../01-general/virt-manager-config/default.nix
    ../02-window-manager-i3/i3/packages.nix
    ../02-window-manager-i3/i3status-rust/packages.nix

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
        distrobox
      ];

      unstable = with unstablePkgs; [
        # firefox
        exploitdb
        netexec
        gh
      ];
    in
    stable ++ unstable;

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
