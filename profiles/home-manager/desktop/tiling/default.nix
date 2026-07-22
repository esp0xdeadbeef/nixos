{ pkgs, ... }:
{
  imports = [
    ./options.nix
    ./fonts.nix
    ./autostart.nix
    ./keybindings.nix
    ./window-rules.nix
    ./copyq.nix
    ./bar.nix
  ];

  home.packages = [
    pkgs.alacritty
    pkgs.firefox
  ];
}
