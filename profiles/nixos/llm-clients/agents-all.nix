{ config, lib, ... }:
let
  apiKeyPath = "/run/secrets/deepseek-api";
in
{
  imports = [ ./agents.nix ];

  local.llmClients.agents.packageNames = lib.mkForce
    config.local.llmClients.agents.runnablePackageNames;

  sops.secrets."deepseek-api" = {
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
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  systemd.tmpfiles.rules = [
    "f /etc/profile.d/deepseek-api-key.sh 0755 root root - -"
  ];

  environment.etc."profile.d/deepseek-api-key.sh".text = ''
    if [ -f ${apiKeyPath} ]; then
      export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${apiKeyPath})"
      export OPENAI_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
}
