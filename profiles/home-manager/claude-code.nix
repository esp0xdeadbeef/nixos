{ config, lib, ... }:
let
  apiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/deepseek-api";
  exportToken = ''
    if [ -f ${apiKeyPath} ]; then
      export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
in
{
  sops.secrets."deepseek-api" = {};

  home.sessionVariables = {
    ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic";
    ANTHROPIC_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash";
    CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-v4-flash";
    CLAUDE_CODE_EFFORT_LEVEL = "max";
  };

  programs.bash.initExtra = exportToken;
  programs.fish.shellInit = lib.mkIf config.programs.fish.enable ''
    if test -f ${apiKeyPath}
      set -gx ANTHROPIC_AUTH_TOKEN (tr -d '\r\n' < ${apiKeyPath})
    end
  '';
  programs.zsh.initExtra = lib.mkIf config.programs.zsh.enable exportToken;
}
