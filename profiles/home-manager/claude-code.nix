{ config, inputs, lib, pkgs, ... }:
let
  apiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/deepseek-api";
  claudeEnv = ''
    export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    export ANTHROPIC_MODEL="deepseek-v4-pro[1m]"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
    export CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
    export CLAUDE_CODE_EFFORT_LEVEL="max"
    if [ -f ${apiKeyPath} ]; then
      export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
in
{
  sops.secrets."deepseek-api" = { };

  home.file.".local/bin/claude" = {
    executable = true;
    text = ''
      #!/bin/sh
      ${claudeEnv}
      exec ${lib.getExe inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code} "$@"
    '';
  };
}
