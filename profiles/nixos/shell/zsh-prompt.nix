{ config
, lib
, name ? null
, pkgs
, self ? null
, ...
}:
let
  cfg = config.local.shell.zshPrompt;
  hostName = config.networking.hostName or "unknown";
  defaultUser = config.local.users.primary.resolvedName;
  hostMap =
    if self == null then
      { }
    else
      self.lib.hosts or { };
  hostPath =
    if name != null && builtins.hasAttr name hostMap then
      hostMap.${name}
    else
      null;
  isServer = hostPath != null && lib.hasPrefix "nixos/server/" hostPath;

  # oh-my-zsh's cache holds one compinit dump for every shell on the host (see
  # the compinit note below), so its owner and mode have to be ones every
  # shell can write, not the ones of whichever user happened to log in first.
  # oh-my-zsh refreshes the dump with `rm -f "$ZSH_COMPDUMP"`, so a cache
  # created by another user (root via `sudo -i`, then the normal user again)
  # makes every later shell print a permission-denied error and rebuild cold.
  # A plain `mkdir` in the shell init cannot fix that, because a normal user
  # cannot chgrp to a group it is not a member of and root must not own a
  # cache the normal user then updates, so the directory is declared in
  # `config` below.
  zshCacheDir = "/persist/var/cache/oh-my-zsh";
  zshCacheGroup = config.users.users.${defaultUser}.group or "users";
  persistMount = config.local.impermanence.persistPath or "/persist";
  hasPersistentRoot = config.local.impermanence.enable or false;

  # oh-my-zsh's compinit is the single largest fixed cost of an interactive
  # shell (~0.5 s cold vs ~35 ms warm).  Two things must be true for it to stay
  # warm:
  #
  #   1. compinit must run ONCE.  NixOS defaults `enableGlobalCompInit` to true,
  #      which emits a bare `compinit` into /etc/zshrc that writes
  #      `$HOME/.zcompdump`; oh-my-zsh then runs compinit again with its own
  #      dump path.  Both were cold on every shell and each paid the full cost.
  #      oh-my-zsh owns compinit here, so the global one is disabled.
  #   2. The dump must survive a reboot.  These hosts boot from a tmpfs root, so
  #      anything under $HOME is discarded and the dump was cold after every
  #      boot.  The dump is redirected under /persist when it is mounted.
  #
  # The dump path is fixed (not host/version templated) because a single
  # persistent path can only back one dump; omz validates the content anyway
  # (it appends its revision + fpath and rebuilds when they change).
  #
  # NOTE: the /persist check is resolved at *runtime* on purpose.  Evaluating it
  # with `builtins.pathExists "/persist"` would probe the machine running the
  # evaluation (the builder / CI), not the host booting the config, and would
  # bake in the wrong answer.

  role =
    if isServer then
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
    if isServer then
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

      variables = {
        EDITOR = "vim";
        VISUAL = "vim";
        HISTSIZE = "100000000";
      };
    };

    # Declare the shared shell cache next to the variable that points at it.
    # `d` creates it on hosts that predate this rule and `Z` re-applies the
    # shared ownership on every boot (tmpfiles processes lines in listed
    # order), so a cache one user already claimed is repaired.  The setgid bit
    # keeps files created inside it on the shared group.  Hosts without a
    # persistent root use the per-user `$HOME/.cache/oh-my-zsh` fallback and
    # need no rule.
    systemd.tmpfiles.rules =
      lib.optionals (hasPersistentRoot && zshCacheDir != persistMount) [
        "d ${zshCacheDir} 2775 root ${zshCacheGroup} -"
        "Z ${zshCacheDir} 2775 root ${zshCacheGroup} -"
      ];

    users.defaultUserShell = lib.mkOverride 900 pkgs.zsh;

    programs.zsh = {
      enable = true;

      # oh-my-zsh below runs compinit itself; the NixOS-generated one in
      # /etc/zshrc would duplicate it (see the compinit note in this module).
      enableGlobalCompInit = lib.mkDefault false;

      shellInit = lib.mkBefore ''
        if [[ -n "$HOME" && "$HOME" != "/" && ! -e "$HOME/.zshrc" ]]; then
          touch -- "$HOME/.zshrc" 2>/dev/null || true
        fi
      '';

      ohMyZsh = {
        enable = true;
        preLoaded = lib.mkBefore ''
          zstyle ':omz:update' mode disabled
          DISABLE_AUTO_UPDATE=true
          DISABLE_UPDATE_PROMPT=true

          # Keep the compinit dump and omz cache off the tmpfs root so a warm
          # dump survives reboots (see the compinit note in this module).
          # Both variables are read by $ZSH/oh-my-zsh.sh, which is sourced after
          # this block.
          if [[ -d ${persistMount} ]]; then
            ZSH_CACHE_DIR=${zshCacheDir}
          else
            ZSH_CACHE_DIR="$HOME/.cache/oh-my-zsh"
          fi
          ZSH_COMPDUMP="''${ZSH_CACHE_DIR}/.zcompdump"
          # The directory is declared by this module's tmpfiles rule on hosts
          # with a persistent root; only step in when it is genuinely missing so
          # a shell never mistakes a permission problem for a missing cache.
          if [[ ! -d "$ZSH_CACHE_DIR" ]]; then
            mkdir -p -- "$ZSH_CACHE_DIR" 2>/dev/null || true
          fi
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
                export EDITOR="''${EDITOR:-vim}"
                export VISUAL="''${VISUAL:-vim}"
                if [[ -d "/persist/$HOME" ]]; then
                  export HISTFILE="/persist/$HOME/.zsh_history"
                elif [[ -z "$HISTFILE" ]]; then
                  export HISTFILE="$HOME/.zsh_history"
                fi
                if [[ -n "$HISTFILE" ]]; then
                  mkdir -p -- "''${HISTFILE:h}" 2>/dev/null || true
                  touch -- "$HISTFILE" 2>/dev/null || true
                fi

                if [[ -r "$HOME/.aliases" ]]; then
                  source "$HOME/.aliases"
                fi

                if [[ -x "${pkgs.fzf}/bin/fzf" ]]; then
                  source <(${pkgs.fzf}/bin/fzf --zsh)
                fi

                if [[ -n "$SSH_CONNECTION" ]]; then
                  typeset __prompt_host_prefix="%F{244}ssh:%F{${color}}"
                else
                  typeset __prompt_host_prefix="%F{${color}}"
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
                    printf ' %%F{244}- %%F{${color}}[%%F{244}%s%%F{${color}}] [%%F{%s}%s%%F{244} %s%%F{${color}}]%%f' "$branch" "$color" "$symbol" "$label"
                  else
                    printf ' %%F{244}- %%F{${color}}[%%F{244}%s%%F{${color}}] [%%F{%s}%s%%F{${color}}]%%f' "$branch" "$color" "$symbol"
                  fi
                }

                PROMPT='%F{${color}}┌─[%B%F{$__prompt_user_color}%n%F{244}@''${__prompt_host_prefix}${hostName}%b%F{${color}}:%F{244}${role}%F{${color}}]%F{244} - %F{${color}}[%F{244}%~%F{${color}}]$(__prompt_git_main_state)%F{244} - %F{${color}}[%F{244}%D{%Y-%m-%d %H:%M}%F{${color}}]%f
        %F{${color}}└─[%(?.%F{green}.%F{red})%#%F{${color}}]%f '
                RPROMPT=""
      '';
    };
  };
}
