{ config, pkgs, ... }:

{

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  environment.systemPackages = with pkgs; [
    obsidian
    vscode
    neovim
    vim
    obsidian
  ];
}
