{ inputs
, outputs
, lib
, config
, pkgs
, outPath
, profiles
, ...
}:
let
  xlayoutdisplayConfig = pkgs.writeText "xlayoutdisplay-l-portal" ''
    wait=2
    rate=60
    dpi=120
    primary=eDP-1
    order=DP-2
    order=DP-1
    order=eDP-1
  '';
in
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
    # hostPlatform = "aarch64-linux";
  };
  home.username = "deadbeef";
  home.homeDirectory = "/home/deadbeef";
  home.enableNixpkgsReleaseCheck = false;
  sops.defaultSopsFile = "${outPath}/secrets/l-portal-default.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  home.file.".xlayoutdisplay".source = xlayoutdisplayConfig;
  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.desktop.legcord.enable = true;
  local.i3.extraConfig = lib.mkAfter ''
    # l-portal additions
    bindsym $mod+F2 exec teams
    bindsym $mod+Print+Shift exec "sway-screenshot -m window -- mirage"

    for_window [class="Slack"] move window to workspace 5
    for_window [class="burp-StartBurp" title="^Burp Suite Professional$"] move container to workspace 10
    for_window [class="burp-StartBurp" title="Automatic project backup"] move container to workspace 10
  '';

  home.packages = with pkgs; [
    htop
    xdotool
    azure-cli
    i3status-rust
    # discord
    obsidian
    # google-chrome
    flameshot
    rofi
    remmina
    spotify-player
    home-manager
  ];

  home.stateVersion = "26.05"; # Match your system state version
}
