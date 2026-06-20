{ config, lib, pkgs, ... }:
let
  cfg = config.local.shell.zshPrompt;
  hostName = config.networking.hostName or "unknown";

  role =
    if hostName == "s-sigma" then
      "server"
    else if lib.hasPrefix "l-" hostName then
      "laptop"
    else if lib.hasPrefix "s-router-" hostName then
      "router-vm"
    else if hostName == "s-agents" then
      "agents-vm"
    else if lib.hasPrefix "s-" hostName then
      "shell-vm"
    else
      "host";

  color =
    if hostName == "s-sigma" then
      "red"
    else if hostName == "l-werk" then
      "green"
    else if hostName == "l-esp" then
      "yellow"
    else if hostName == "l-x13s" then
      "cyan"
    else if hostName == "s-agents" then
      "magenta"
    else if lib.hasPrefix "s-router-" hostName then
      "cyan"
    else if lib.hasPrefix "s-" hostName then
      "blue"
    else
      "white";
in
{
  options.local.shell.zshPrompt = {
    enable = lib.mkEnableOption "deterministic zsh prompt";
  };

  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = with pkgs; [
        fzf
      ];

      variables.HISTSIZE = "100000000";
    };

    programs.zsh = {
      enable = true;

      ohMyZsh = {
        enable = true;
        preLoaded = lib.mkBefore ''
          zstyle ':omz:update' mode disabled
          DISABLE_AUTO_UPDATE=true
          DISABLE_UPDATE_PROMPT=true
        '';
        plugins = [
          "fzf"
          "sudo"
          "systemadmin"
        ];
        theme = lib.mkForce "";
      };

      interactiveShellInit = lib.mkAfter ''
        setopt prompt_subst
        setopt hist_ignore_all_dups
        setopt share_history
        autoload -Uz colors && colors

        export HISTSIZE=1000000000
        export SAVEHIST=1000000000
        if [[ -z "$HISTFILE" ]]; then
          if [[ -d "/persist/$HOME" ]]; then
            export HISTFILE="/persist/$HOME/.zsh_history"
          else
            export HISTFILE="$HOME/.zsh_history"
          fi
        fi

        if [[ -r "$HOME/.aliases" ]]; then
          source "$HOME/.aliases"
        fi

        if [[ -x "${pkgs.fzf}/bin/fzf" ]]; then
          source <(${pkgs.fzf}/bin/fzf --zsh)
        fi

        if [[ -n "$SSH_CONNECTION" ]]; then
          typeset __prompt_host="ssh:${hostName}"
        else
          typeset __prompt_host="${hostName}"
        fi

        PROMPT='%F{${color}}┌─[%B%n@$__prompt_host%b:%F{244}${role}%F{${color}}] - %F{blue}[%~]%F{${color}} - %F{244}[%D{%a %b %d, %H:%M}]%f
%F{${color}}└─%f%(?.%F{green}.%F{red})[%#]%f '
        RPROMPT=""
      '';
    };
  };
}
