{ pkgs, nixpkgs-unstable, ... }:

{
  home.packages = with pkgs; [
    htop
    teams-for-linux
    intune-portal
    microsoft-edge
    xdotool
    azure-cli
    i3status-rust
    discord
    obsidian
    autorandr
    vscode
    google-chrome
    flameshot
    rofi
    remmina
    mitmproxy
    netexec
    #exploitdb
    nixpkgs-unstable.legacyPackages.x86_64-linux.exploitdb
    (nixpkgs-unstable.legacyPackages.x86_64-linux.burpsuite.override { proEdition = true; })
  ];
}

