{ config, pkgs, ... }:
{
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [
    vim
    fzf
    networkmanager
    # konsole
    tmux
    i3blocks
    i3status
  ];
}
