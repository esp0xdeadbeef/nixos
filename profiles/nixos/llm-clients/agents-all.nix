{ config, lib, ... }:
{
  imports = [ ./agents.nix ];

  local.llmClients.agents.packageNames = lib.mkForce
    config.local.llmClients.agents.runnablePackageNames;

  sops.secrets."deepseek-api" = {
    owner = "deadbeef";
    group = "users";
    mode = "0400";
  };
}
