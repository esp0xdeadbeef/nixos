# ./default.nix
{
  outPath,
  lib,
  config,
  ...
}:

let
  fabricInputs = import "${outPath}/library/100-fabric-routing/inputs/intent.nix";
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./fabric-input-loader.nix
    ./host-network
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
  ];

  _module.args.fabricInputs = fabricInputs;
}
