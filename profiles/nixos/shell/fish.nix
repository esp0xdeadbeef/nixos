{ config
, lib
, options
, pkgs
, ...
}:

let
  usesSharedImpermanence =
    options ? local
    && options.local ? impermanence
    && config.local.impermanence.enable;
in
{
  programs.fish.enable = true;
  programs.zsh.enable = true;

  users.defaultUserShell = lib.mkDefault pkgs.zsh;

  environment.systemPackages = with pkgs; [
    fish
    zsh
    fzf
    zoxide
    starship
    fd
    ripgrep
    bat
    eza
    gh
  ];

  programs.git = {
    enable = true;

    config = {
      credential."https://github.com".helper = "!gh auth git-credential";
      credential."https://gist.github.com".helper = "!gh auth git-credential";

      init.defaultBranch = "main";
      pull.rebase = false;
      push.autoSetupRemote = true;

      core.editor = "vim";
    };
  };

  programs.fish = {
    shellAbbrs = {
      # General.
      c = "clear";
      q = "exit";
      ll = "eza -lah --group-directories-first --icons=auto";
      la = "eza -la --group-directories-first --icons=auto";
      l = "eza -lah --group-directories-first --icons=auto";
      tree = "eza --tree --icons=auto";
      cat = "bat";
      grep = "rg";

      # Navigation.
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";

      # Git.
      g = "git";
      gs = "git status --short --branch";
      gst = "git status";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit";
      gcm = "git commit -m";
      gca = "git commit --amend";
      gcan = "git commit --amend --no-edit";
      gp = "git push";
      gpf = "git push --force-with-lease";
      gl = "git log --oneline --graph --decorate";
      gd = "git diff";
      gds = "git diff --staged";
      gb = "git branch";
      gba = "git branch --all";
      gco = "git checkout";
      gsw = "git switch";
      gsc = "git switch -c";
      gf = "git fetch --all --prune";
      gr = "git rebase";
      gri = "git rebase -i";
      grc = "git rebase --continue";
      gra = "git rebase --abort";

      # Nix.
      ns = "nix shell";
      nb = "nix build";
      nf = "nix flake";
      nfu = "nix flake update";
      nfc = "nix flake check";
      nr = "sudo nixos-rebuild switch --flake";
      nrb = "sudo nixos-rebuild boot --flake";

      # Workspace.
      ghh = "cd ~/github";
      nxs = "cd ~/github/nixos";
    };

    shellAliases = {
      ls = "eza --group-directories-first --icons=auto";
      ip = "ip --color=auto";
    };

    interactiveShellInit = ''
      # No greeting.
      set fish_greeting

      # Default editor.
      if not set -q EDITOR
        set -gx EDITOR vim
      end

      # Secrets / GitHub auth.
      if test -r /run/secrets/gh-token
        set -gx GH_TOKEN (cat /run/secrets/gh-token)
        set -gx GITHUB_TOKEN $GH_TOKEN
      end

      # fzf defaults.
      set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --inline-info"
      set -gx FZF_DEFAULT_COMMAND "fd --type f --hidden --follow --exclude .git"
      set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
      set -gx FZF_ALT_C_COMMAND "fd --type d --hidden --follow --exclude .git"

      # Better default tools.
      set -gx BAT_STYLE "numbers,changes,header"
      set -gx LESS "-R"
      set -gx NIXPKGS_ALLOW_UNFREE 1

      # Try upstream fzf fish integration first. This should provide normal
      # Ctrl-T / Ctrl-R / Alt-C behavior on modern fzf.
      if type -q fzf
        fzf --fish | source
      end

      # zoxide: smarter cd.
      if type -q zoxide
        zoxide init fish | source
      end

      # starship prompt.
      if type -q starship
        starship init fish | source
      end

      # Bash-style previous-command expansion.
      function __deadbeef_last_history_item
        echo $history[1]
      end

      abbr --add !! --position anywhere --function __deadbeef_last_history_item

      # --- Hard fzf bindings ---
      # These are explicit so Ctrl-R works even if fzf's packaged fish
      # integration changes names, paths, or load order.

      function __deadbeef_fzf_history
        set -l selected (
          history |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --query=(commandline) \
            --preview-window=hidden
        )

        if test -n "$selected"
          commandline --replace -- "$selected"
          commandline --cursor (string length -- "$selected")
        end

        commandline --function repaint
      end

      function __deadbeef_fzf_file_insert
        set -l selected (
          fd --type f --hidden --follow --exclude .git . |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'bat --style=numbers --color=always --line-range :200 {} 2>/dev/null or sed -n "1,200p" {}' \
            --preview-window=right:60%
        )

        if test -n "$selected"
          commandline --insert -- (string escape -- "$selected")
        end

        commandline --function repaint
      end

      function __deadbeef_fzf_cd
        set -l selected (
          fd --type d --hidden --follow --exclude .git . |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'eza -lah --group-directories-first --icons=auto {} 2>/dev/null or ls -lah {}' \
            --preview-window=right:50%
        )

        if test -n "$selected"
          cd "$selected"
          commandline --function repaint
        end
      end

      # Explicit shell keybindings.
      #
      # Ctrl-R  history search
      # Ctrl-T  insert file path
      # Alt-C   cd into selected directory
      bind \cr __deadbeef_fzf_history
      bind \ct __deadbeef_fzf_file_insert
      bind \ec __deadbeef_fzf_cd

      # If fish is in vi mode later, make insert mode work too.
      bind -M insert \cr __deadbeef_fzf_history 2>/dev/null
      bind -M insert \ct __deadbeef_fzf_file_insert 2>/dev/null
      bind -M insert \ec __deadbeef_fzf_cd 2>/dev/null

      # --- Extra workflow functions ---

      function cdf
        __deadbeef_fzf_cd
      end

      function vf
        set -l file (
          fd --type f --hidden --follow --exclude .git . |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'bat --style=numbers --color=always --line-range :200 {} 2>/dev/null or sed -n "1,200p" {}' \
            --preview-window=right:60%
        )

        if test -n "$file"
          $EDITOR "$file"
        end
      end

      function rgf
        if test (count $argv) -eq 0
          echo "usage: rgf <pattern>"
          return 1
        end

        set -l selected (
          rg \
            --line-number \
            --column \
            --hidden \
            --glob '!.git' \
            --color=always \
            "$argv" |
          fzf \
            --ansi \
            --height 80% \
            --layout=reverse \
            --border \
            --delimiter ':' \
            --preview 'bat --color=always --style=numbers --highlight-line {2} {1} 2>/dev/null' \
            --preview-window=right:60%
        )

        if test -n "$selected"
          set -l file (string split ':' "$selected")[1]
          set -l line (string split ':' "$selected")[2]
          $EDITOR +"$line" "$file"
        end
      end

      function gsf
        set -l branch (
          git branch --all --color=always |
          sed 's/^[* ]*//' |
          sed 's#remotes/origin/##' |
          sort -u |
          fzf \
            --ansi \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'git log --oneline --graph --decorate --color=always {} -- 2>/dev/null | head -200'
        )

        if test -n "$branch"
          git switch "$branch"
        end
      end

      function gdf
        set -l file (
          git diff --name-only |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --preview 'git diff --color=always -- {}' \
            --preview-window=right:60%
        )

        if test -n "$file"
          git diff -- "$file"
        end
      end

      function pkf
        set -l pid (
          ps -ef |
          sed 1d |
          fzf \
            --height 40% \
            --layout=reverse \
            --border \
            --header='Select process to kill' |
          awk '{print $2}'
        )

        if test -n "$pid"
          kill -9 "$pid"
        end
      end
    '';
  };

  environment.persistence = lib.mkIf ((options.environment ? persistence) && !usesSharedImpermanence) {
    "/persist" = {
      users.deadbeef.directories = [
        ".local/share/fish"
        ".local/share/zoxide"
        ".config/fish"
        ".config/starship"
        ".config/ripgrep"
      ];

      users.root.directories = [
        ".local/share/fish"
        ".local/share/zoxide"
        ".config/fish"
        ".config/starship"
        ".config/ripgrep"
      ];
    };
  };
}
