args@{ inputs
, outputs
, config
, outPath
, profiles
, ...
}:
let
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
in
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    profiles.home-manager.desktop.legcord
    profiles.home-manager.desktop-i3
    # profiles.home-manager.desktop-sway
    ./desktop.nix
    ./rclone-wrapper/rclone.nix
    ./remmina/config.nix
    ./work-microsoft.nix

    inputs.sops-nix.homeManagerModules.sops
  ];

  sops = {
    defaultSopsFile = "${outPath}/secrets/${hostName}-default-${config.home.username}.yaml";

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
  # Enable home-manager
  programs.home-manager.enable = true;
  local.i3.statusRust.battery.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";

}
