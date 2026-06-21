args@{ inputs
, outputs
, lib
, config
, pkgs
, outPath
, profiles
, sopsSecrets
, ...
}:
let
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
  _ = builtins.trace "HOME.NIX got: ${lib.concatStringsSep ", " (builtins.attrNames args)}" null;
  #unstablePkgs = import inputs.nixpkgs-unstable {
  #  system = pkgs.stdenv.hostPlatform.system;
  #  config.allowUnfree = true;
  #};
  unstablePkgs = pkgs.unstable;
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
    profiles.home-manager.desktop.legcord
    profiles.home-manager.desktop-i3
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
  local.i3.statusCommand = "${pkgs.i3status-rust}/bin/i3status-rs ~/.config/i3status-rust/config.toml";
  local.desktop.legcord.enable = true;
  local.i3.extraConfig = lib.mkAfter ''
    # l-envil additions
    #bindsym $mod+m mode "exit: [l]ogout, [r]eboot, [s]hutdown"
    bindsym $mod+F2 exec teams
    bindsym $mod+Print+Shift exec "sway-screenshot -m window -- mirage"
    bindsym $mod+o exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-office-libvirt.remmina"
    bindsym $mod+p exec ${pkgs.remmina}/bin/remmina -c "/home/deadbeef/.local/share/remmina/group_rdp_1-win11-pentest-libvirt.remmina"

    for_window [class="burp-StartBurp" title="^Burp Suite Professional$"] move container to workspace 10
    for_window [class="burp-StartBurp" title="Automatic project backup"] move container to workspace 10
    for_window [class="Slack"] move window to workspace 5
    ${lib.optionalString config.local.work.microsoft.enable ''
      for_window [class="teams-for-linux"] move window to workspace 5
    ''}
    ${lib.optionalString config.local.work.microsoft.enable ''
      exec --no-startup-id ${pkgs.teams-for-linux}/bin/teams-for-linux
    ''}
  '';

  home.packages =
    let
      stable = with pkgs; [
        htop
        # need this because screenshareing is fcked because microslob is doing its thing:
        #teams-for-linux
        xdotool
        i3status-rust
        discord
        obsidian
        google-chrome
        flameshot
        rofi
        remmina
        black
        tmuxp

      ];
      unstable = with unstablePkgs; [
        # firefox
        slack
        gh
      ];
    in
    stable ++ unstable;

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";

}
