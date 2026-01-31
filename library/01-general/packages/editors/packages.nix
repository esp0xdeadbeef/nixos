{ config, pkgs, ... }:

{

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  programs.direnv.enable = true;
  programs.direnv.enableZshIntegration = true;

  environment.systemPackages = with pkgs; [
    obsidian
    # vscode
    # neovim
    vim
    obsidian
  ];
}
