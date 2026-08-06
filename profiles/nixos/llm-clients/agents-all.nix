{ config, inputs, lib, pkgs, ... }:
let
  apiKeyPath = "/run/secrets/deepseek-api";

  baseEnv = {
    ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic";
    ANTHROPIC_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_OPUS_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_SONNET_MODEL = "deepseek-v4-pro[1m]";
    ANTHROPIC_DEFAULT_HAIKU_MODEL = "deepseek-v4-flash";
    CLAUDE_CODE_SUBAGENT_MODEL = "deepseek-v4-flash";
    OPENAI_BASE_URL = "https://api.deepseek.com/v1";
  };

  wrapAgent = name: pkg:
    pkgs.writeShellScriptBin name ''
      if [ -f ${apiKeyPath} ]; then
        export ANTHROPIC_AUTH_TOKEN="$(tr -d '\r\n' < ${apiKeyPath})"
        export OPENAI_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
        export DEEPSEEK_API_KEY="$(tr -d '\r\n' < ${apiKeyPath})"
      fi
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}='${v}'") baseEnv)}
      exec ${lib.getExe pkg} "$@"
    '';

  registry = import ./registry.nix { inherit lib inputs pkgs; };
  allPackages = lib.filterAttrs (_n: p: lib.isDerivation p && p ? meta && p.meta ? mainProgram) registry.packageSet;
  wrappedPackages = lib.mapAttrs' (name: pkg: lib.nameValuePair "llm-${name}" (wrapAgent name pkg)) allPackages;
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

  environment.systemPackages = builtins.attrValues wrappedPackages;
}
