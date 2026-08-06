{ config, lib, ... }:
let
  apiKeyPath = "/run/secrets/deepseek-api";
  exportKeys = ''
    if [ -f ${apiKeyPath} ]; then
      export OPENAI_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
      export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
    fi
  '';
in
{
  home.sessionVariables = {
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  programs.bash.initExtra = lib.mkAfter exportKeys;
  programs.zsh.initExtra = lib.mkAfter exportKeys;
  programs.fish.shellInit = lib.mkIf config.programs.fish.enable (
    lib.mkAfter ''
      if test -f ${apiKeyPath}
        set -gx OPENAI_API_KEY (tr -d '\r\n' < ${apiKeyPath})
        set -gx DEEPSEEK_API_KEY (tr -d '\r\n' < ${apiKeyPath})
      end
    ''
  );
}
