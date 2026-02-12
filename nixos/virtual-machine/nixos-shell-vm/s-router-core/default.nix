# FILE: ./s-router-core/default.nix
# ./default.nix
{
  outPath,
  lib,
  config,
  ...
}:

let
  fabricInputs = import "${outPath}/library/100-fabric-routing/inputs";
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./host-network.nix
    ./mount-utils.nix
    ./container-settings.nix
    ./debugging-packages.nix
    ./sops.nix
  ];

  _module.args.fabricInputs = fabricInputs;
}

