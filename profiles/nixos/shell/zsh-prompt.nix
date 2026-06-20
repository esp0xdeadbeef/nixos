{ config, lib, ... }:
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
    programs.zsh = {
      enable = true;

      ohMyZsh = {
        preLoaded = lib.mkBefore ''
          zstyle ':omz:update' mode disabled
          DISABLE_AUTO_UPDATE=true
          DISABLE_UPDATE_PROMPT=true
        '';
        theme = lib.mkForce "";
      };

      interactiveShellInit = lib.mkAfter ''
        setopt prompt_subst
        autoload -Uz colors && colors

        if [[ -n "$SSH_CONNECTION" ]]; then
          typeset __prompt_transport="ssh:"
        else
          typeset __prompt_transport=""
        fi

        PROMPT='%B%F{${color}}['"$__prompt_transport"'${role}:${hostName}]%f%b %F{white}%~%f %(?.%F{green}.%F{red})%#%f '
        RPROMPT='%F{244}%*%f'
      '';
    };
  };
}
