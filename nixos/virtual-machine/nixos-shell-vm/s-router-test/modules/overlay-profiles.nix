{ lib }:

let
  networkModules = import ./overlay-network-modules.nix;
  basic = import ./overlay-profile-basic.nix { inherit networkModules; };
in
{
  forName =
    profile: _nodeSpec:
    if profile == "core-client" then
      basic.coreClient
    else if profile == "core-router-nebula" then
      basic.coreRouterNebula
    else if profile == "branch-web" then
      basic.branchWeb
    else if profile == "hostile-exit" then
      basic.coreClient
    else if profile == "storage-client" then
      basic.storageClient
    else
      throw "Unsupported overlay runtime node container profile: ${profile}";
}
