{ config, pkgs, ... }:
{

  # also check nix-index btw :)
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    localuser = null;
    # prunePaths = options.services.locate.prunePaths.default ++ [ "/mnt/pool" ];
  };
  environment.systemPackages = with pkgs; [
    navi
    rlwrap
    sshpass
    # easier searching:
    fzf
    tmux
  ];
}
