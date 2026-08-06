{ inputs, lib, pkgs, ... }:
let
  registry = import ./registry.nix { inherit inputs lib pkgs; };
in
{
  imports = [ ./agents.nix ];

  local.llmClients.agents.packageNames = lib.mkForce
    (builtins.attrNames
      (builtins.intersectAttrs registry.runnablePackages registry.persistenceByPackageName));

  sops.secrets."deepseek-api" = lib.mkDefault {
    owner = "deadbeef";
    group = "users";
    mode = "0400";
  };
}
