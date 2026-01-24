{ config, pkgs, ... }:
{
  environment.variables.HISTSIZE = "100000000";
  environment.interactiveShellInit = ''
    if [ -f ~/.aliases ]; then
      source ~/.aliases
    fi

  '';
  users.defaultUserShell = pkgs.zsh;
  environment.systemPackages = with pkgs; [
    fzf
    navi
  ];

  programs.zsh = {
    enable = true;
    interactiveShellInit = ''
      export HISTSIZE=1000000000
      export SAVEHIST=1000000000
      export HISTFILE="/persist/$HOME/.zsh_history"
      source <(fzf --zsh)
      # eval "$(navi widget zsh)"
      source <(op completion zsh 2>/dev/null || true)
    '';
    ohMyZsh = {
      enable = true;
      plugins = [
        "sudo"
        "terraform"
        "systemadmin"
        "fzf"
      ];
    };

  };

}
