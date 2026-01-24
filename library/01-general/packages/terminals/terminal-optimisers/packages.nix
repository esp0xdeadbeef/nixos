{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    navi
    rlwrap
    sshpass
    # easier searching:
    fzf
    tmux
  ];
}
