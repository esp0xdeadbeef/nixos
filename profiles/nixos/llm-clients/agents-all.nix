{ config, inputs, lib, pkgs, ... }:
let
  registry = import ./registry.nix { inherit inputs lib pkgs; };
in
{
  imports = [ ./agents.nix ];

  local.llmClients.agents.packageNames = lib.mkForce
    (builtins.attrNames registry.runnablePackages);

  sops.secrets."deepseek-api" = lib.mkDefault {
    owner = "deadbeef";
    group = "users";
    mode = "0400";
  };
}
