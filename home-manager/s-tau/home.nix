# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, profiles
, hostName
, outPath
, ...
}:
let
  sopsFile = "${outPath}/secrets/${hostName}-root.yaml";
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    profiles.home-manager.desktop.i3
    "${outPath}/profiles/home-manager/nix/github-access-token.nix"
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
  };
  home.enableNixpkgsReleaseCheck = false;
  home = {
    username = "deadbeef";
    homeDirectory = "/home/deadbeef";
  };
  local.i3.modifier = "Mod1";
  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.i3.spotify.enable = false;

  home.packages = with pkgs; [
    btop
    htop
    tmuxp
  ];
  # Enable home-manager and git
  programs.home-manager.enable = true;
  programs.git = { enable = true; signing.format = null; };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";

} // lib.optionalAttrs (builtins.pathExists sopsFile) {
  sops.defaultSopsFile = sopsFile;
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
}
