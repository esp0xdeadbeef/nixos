{ config, pkgs, lib, ... }:
let
  # profiles/nixos/shell/zsh-prompt.nix is the canonical interactive zsh owner and
  # is imported by every nixos-shell host.  This module is additionally imported
  # for desktop tooling (fzf/navi).  When both are present, NixOS concatenates
  # `programs.zsh.ohMyZsh.plugins` and `interactiveShellInit`, which used to
  # duplicate every plugin (`... fzf fzf sudo systemadmin`) and re-run
  # `op completion zsh` + `fzf --zsh` a second time.  Only contribute the
  # oh-my-zsh/init here when the canonical profile is not in use, so this module
  # stays self-sufficient for hosts that import it alone (e.g. s-test-l-esp).
  ownsZsh = !(config.local.shell.zshPrompt.enable or false);
in
{
  environment.variables.HISTSIZE = "100000000";

  users.defaultUserShell = pkgs.zsh;

  environment.systemPackages = with pkgs; [
    fzf
    navi
  ];

  environment.interactiveShellInit = lib.mkIf ownsZsh ''
    if [ -f ~/.aliases ]; then
      source ~/.aliases
    fi
  '';

  programs.zsh = {
    enable = true;

    interactiveShellInit = lib.mkIf ownsZsh ''
      export HISTSIZE=1000000000
      export SAVEHIST=1000000000
      # Only point the history at /persist when it actually exists; otherwise
      # this would create a literal /persist/... path on tmpfs-only systems.
      if [[ -d /persist ]]; then
        export HISTFILE="/persist/$HOME/.zsh_history"
      fi
      source <(fzf --zsh)
      # `op` is shell completion only; never fail or block a shell on it.
      if command -v op >/dev/null 2>&1; then
        source <(op completion zsh 2>/dev/null || true)
      fi
    '';

    ohMyZsh = lib.mkIf ownsZsh {
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
