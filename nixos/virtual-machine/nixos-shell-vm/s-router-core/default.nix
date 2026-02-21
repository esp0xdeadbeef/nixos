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
    ./host-network
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
    ./fabric-input-loader.nix
  ];

  _module.args.fabricDebug = true;
  _module.args.fabricInputs = fabricInputs;
}
