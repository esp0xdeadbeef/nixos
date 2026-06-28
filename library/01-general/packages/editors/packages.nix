{ config, pkgs, ... }:

{

  programs.neovim = {
    enable = true;
  };

  programs.direnv.enable = true;
  programs.direnv.enableZshIntegration = true;

  environment.systemPackages = with pkgs; [
    # vscode
    # neovim
    vim
  ];
}
