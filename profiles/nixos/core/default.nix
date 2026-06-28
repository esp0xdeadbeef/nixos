{ pkgs, profiles, ... }:
{
  imports = [
    profiles.nixos.base.common
  ];

  programs.nano.enable = false;

  environment.systemPackages = with pkgs; [
    binutils
    btop
    openssl
    sshpass
    tmuxp
    vim
  ];
}
