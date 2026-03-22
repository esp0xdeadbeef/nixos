{
  outPath,
  lib,
  config,
  ...
}:

let
  fabricPath = "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  fabricImported =
    if builtins.pathExists fabricPath then
      import fabricPath
    else
      { };

  fabricInputs =
    if builtins.isFunction fabricImported then
      fabricImported { inherit lib; }
    else
      fabricImported;
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./host-network.nix
    ./mount-utils.nix
    ./container/container-settings.nix
    ./debugging-packages.nix
    ./sops.nix
    ./fabric-input-loader.nix
  ];

  _module.args.fabricInputs = fabricInputs;
}
