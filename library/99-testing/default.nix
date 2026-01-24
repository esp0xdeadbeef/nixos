{ pkgs, ... }:
{
  imports = [
    ./enable-ssh-with-authorized-keys-and-add-NOPASSWD.nix
    ./autologin.nix
  ];
}
