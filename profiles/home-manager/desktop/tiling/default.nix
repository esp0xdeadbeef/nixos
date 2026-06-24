{ outPath, ... }:
{
  imports = [
    ./options.nix
    ./fonts.nix
    ./autostart.nix
    ./keybindings.nix
    ./window-rules.nix
    ./bar.nix
  ];
}
