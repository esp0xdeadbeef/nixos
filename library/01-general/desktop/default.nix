{ pkgs, ... }:
{
  imports = [
    ./applet-nm.nix
    ./fonts.nix
    ./packages.nix
    ./screen-recording.nix
    ./shell-env.nix
    ./users-and-groups.nix
    ./xdg-portal.nix
  ];
}
