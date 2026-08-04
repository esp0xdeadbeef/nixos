{ config, lib, ... }:
{
  local.llmClients.agents.packageNames = lib.mkAfter [ "claude-code" ];

  sops.secrets."deepseek-api" = {
    owner = "deadbeef";
    group = "users";
    mode = "0400";
  };
}
