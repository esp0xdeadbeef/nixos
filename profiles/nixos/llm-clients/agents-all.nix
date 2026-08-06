{ config, lib, ... }:
{
  imports = [ ./agents.nix ];

  local.llmClients.agents.packageNames = lib.mkForce
    config.local.llmClients.agents.runnablePackageNames;
}
