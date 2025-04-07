{
  config,
  pkgs,
  nixpkgs-unstable,
  ...
}:

{
  systemd.user.services.searchsploit-update = {
    description = "Update SearchSploit";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # serviceConfig = {
    #   type = "oneshot";
    #   ExecStart = "${pkgs.exploitdb}/bin/searchsploit -u";
    # };
    serviceConfig = {
      ExecStart = "${pkgs.exploitdb}/bin/searchsploit -u";
      Restart = "on-failure";
    };
  };

  systemd.user.timers.searchsploit-update = {
    description = "Run SearchSploit Update Daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      onCalendar = "daily";
      persistent = true;
    };
  };

  systemd.user.services.dropbox = {
    description = "Dropbox service";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.dropbox}/bin/dropbox";
      Restart = "on-failure";
    };
  };

  #nixpkgs.config.allowUnfree = true;
  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.deadbeef = {
      # Replace with your username
      home.enableNixpkgsReleaseCheck = false;
      home.stateVersion = "24.11"; # Match your system state version

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
        rofi
        remmina
        mitmproxy
        dropbox

      ];
    };
  };
}
