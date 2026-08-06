{ config, lib, ... }:
let
  apiKeyPath = "${config.home.homeDirectory}/.config/sops-nix/secrets/deepseek-api";
in
{
  sops.secrets."deepseek-api" = {};

  home.sessionVariables = {
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  home.file.".zshenv".text = ''
    if [ -f ${apiKeyPath} ]; then
      export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${apiKeyPath})"
      export OPENAI_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
}
