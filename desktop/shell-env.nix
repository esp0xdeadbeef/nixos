{ config, pkgs, ... }:
{
  environment.variables.HISTSIZE = "100000000";
  environment.interactiveShellInit = ''
    if [ -f ~/.aliases ]; then
      source ~/.aliases
    fi
    (
    cd $(env | grep '^ZSH=.*-oh-my-zsh-.*' | cut -d '=' -f 2)
    source ./oh-my-zsh.sh 2>/dev/null
    )
  '';
  

  users.defaultUserShell = pkgs.zsh;

  programs.zsh = {
    enable = true;
    interactiveShellInit = ''
      export HISTSIZE=1000000
      export SAVEHIST=1000000
      source <(fzf --zsh)
    '';
    ohMyZsh = {
      enable = true;
      #theme = "random";
      #theme = "clean";
      plugins = [
        "sudo"
        "terraform"
        "systemadmin"
        "vi-mode"
        "fzf"
      ];
    };

  };

}
