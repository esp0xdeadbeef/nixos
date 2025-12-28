{ pkgs, ... }:
{
  imports = [
    ./autologin-ssh-and-tty.nix
    ./autologin.nix
  ];
}
