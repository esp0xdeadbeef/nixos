{ inputs, lib, pkgs, ... }:
let
  registry = import ./registry.nix { inherit inputs lib pkgs; };
in
{
  imports = [ ./agents.nix ];

  # Every runnable llm-agents package that has explicit persistence metadata.
  #
  # This profile selects *packages* only: it must not declare provider secrets.
  # A host that wants a provider (e.g. the DeepSeek-backed Claude Code wrapper)
  # imports the matching provider profile, e.g. ./claude-deepseek.nix, which is
  # where `sops.secrets."deepseek-api"` belongs. Declaring it here would make
  # every host that just wants the agent CLIs fail its sops manifest check for
  # a key it never asked for.
  local.llmClients.agents.packageNames = lib.mkForce
    (builtins.attrNames
      (builtins.intersectAttrs registry.runnablePackages registry.persistenceByPackageName));
}
