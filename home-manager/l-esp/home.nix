{ config, pkgs, nixpkgs-unstable, ... }:


{
  systemd.user.services.searchsploit-update = {
    description = "Update SearchSploit";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      type = "oneshot";
      execStart = "${pkgs.exploitdb}/bin/searchsploit -u";
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

  
  #nixpkgs.config.allowUnfree = true;
  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.deadbeef = {  # Replace with your username
      home.enableNixpkgsReleaseCheck = false;
      home.stateVersion = "24.11";  # Match your system state version
      
      home.packages = with pkgs; [
        htop
        xdotool
        azure-cli
        i3status-rust
        discord
        obsidian
        vscode
        google-chrome
        flameshot
        rofi
        remmina
        mitmproxy
        
      ];
    };
  };
}
