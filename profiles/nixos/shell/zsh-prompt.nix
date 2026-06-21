{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.local.shell.zshPrompt;
  hostName = config.networking.hostName or "unknown";
  defaultUser = config.local.users.primary.resolvedName;

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
    else if hostName == "l-envil" then
      "green"
    else if hostName == "l-esp" then
      "yellow"
    else if hostName == "l-portal" then
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

    users.defaultUserShell = lib.mkOverride 900 pkgs.zsh;

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

                if [[ "$USER" == "root" ]]; then
                  typeset __prompt_user_color="red"
                elif [[ "$USER" == "${defaultUser}" ]]; then
                  typeset __prompt_user_color="green"
                else
                  typeset __prompt_user_color="blue"
                fi

                __prompt_git_main_state() {
                  local git_dir branch upstream head upstream_head symbol color label
                  local -a git_timeout

                  git_timeout=("${pkgs.coreutils}/bin/timeout" "0.3")
                  git_cmd="${pkgs.git}/bin/git"
                  git_dir="$("''${git_timeout[@]}" "$git_cmd" rev-parse --git-dir 2>/dev/null)" || return 0
                  [[ -n "$git_dir" ]] || return 0

                  branch="$("''${git_timeout[@]}" "$git_cmd" symbolic-ref --quiet --short HEAD 2>/dev/null || "''${git_timeout[@]}" "$git_cmd" rev-parse --short HEAD 2>/dev/null)" || branch="detached"
                  upstream="$("''${git_timeout[@]}" "$git_cmd" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" || upstream=""
                  head="$("''${git_timeout[@]}" "$git_cmd" rev-parse --verify HEAD 2>/dev/null)" || return 0
                  upstream_head="$(
                    if [[ -n "$upstream" ]]; then
                      "''${git_timeout[@]}" "$git_cmd" rev-parse --verify "$upstream" 2>/dev/null
                    fi
                  )"

                  if [[ -z "$upstream" ]]; then
                    symbol="✗"
                    color="red"
                    label="no-upstream"
                  elif ! "''${git_timeout[@]}" "$git_cmd" diff --quiet --ignore-submodules -- 2>/dev/null || ! "''${git_timeout[@]}" "$git_cmd" diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
                    symbol="✗"
                    color="red"
                    label="dirty"
                  elif [[ -z "$upstream_head" || "$head" != "$upstream_head" ]]; then
                    symbol="✗"
                    color="red"
                    label="$upstream"
                  else
                    symbol="✓"
                    color="green"
                    label=""
                  fi

                  if [[ -n "$label" ]]; then
                    printf ' - %%F{244}[%s]%%f %%F{%s}[%s %s]%%f' "$branch" "$color" "$symbol" "$label"
                  else
                    printf ' - %%F{244}[%s]%%f %%F{%s}[%s]%%f' "$branch" "$color" "$symbol"
                  fi
                }

                PROMPT='%F{${color}}┌─[%B%F{$__prompt_user_color}%n%F{${color}}@$__prompt_host%b:%F{244}${role}%F{${color}}] - %F{244}[%~]%F{${color}}$(__prompt_git_main_state) - %F{244}[%D{%a %b %d, %H:%M}]%f
        %F{${color}}└─%f%(?.%F{green}.%F{red})[%#]%f '
                RPROMPT=""
      '';
    };
  };
}
