{ config, lib, relativeRepo, ... }:
{
  local.llmClients.agents.packageNames = lib.mkAfter [ "claude-code" ];

  sops.secrets."deepseek-api" = {
    sopsFile = relativeRepo.sourcePath "secrets/l-esp-default-deadbeef.yaml";
    owner = "deadbeef";
    group = "users";
    mode = "0400";
  };

  environment.variables = {
    ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic";
    ANTHROPIC_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash";
    CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-v4-flash";
    CLAUDE_CODE_EFFORT_LEVEL = "max";
  };

  environment.shellInit = ''
    if [ -f ${config.sops.secrets."deepseek-api".path} ]; then
      export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${config.sops.secrets."deepseek-api".path})"
    fi
  '';
}
