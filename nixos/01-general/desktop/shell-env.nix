{ config, pkgs, ... }:
{
  environment.variables.HISTSIZE = "100000000";
  environment.interactiveShellInit = ''
    if [ -f ~/.aliases ]; then
      source ~/.aliases
    fi

  '';
  users.defaultUserShell = pkgs.zsh;

  programs.zsh = {
    enable = true;
    interactiveShellInit = ''
      export HISTSIZE=1000000000
      export SAVEHIST=1000000000
      source <(fzf --zsh)
      source <(op completion zsh 2>/dev/null || true)
    '';
    ohMyZsh = {
      enable = true;
      #theme = "random";
      #theme = "clean";
      plugins = [
        "sudo"
        "terraform"
        "systemadmin"
        # "vi-mode"
        "fzf"
      ];
    };

  };

}
