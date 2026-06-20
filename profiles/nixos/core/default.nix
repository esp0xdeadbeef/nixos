{ pkgs, profiles, ... }:
{
  imports = [
    profiles.nixos.base.common
    profiles.nixos.editors.neovim
  ];

  programs.nano.enable = false;

  environment.systemPackages = with pkgs; [
    btop
    sshpass
    tmuxp
    vim
  ];
}
