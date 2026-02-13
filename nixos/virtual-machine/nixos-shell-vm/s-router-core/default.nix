# ./default.nix
# FILE: ./s-router-core/default.nix
{
  inputs,
  outPath,
  lib,
  config,
  ...
}:

let
  inputsPath = "${outPath}/library/100-fabric-routing/inputs";

  imported = import inputsPath;

  fabricInputs =
    if builtins.isFunction imported then
      imported { sopsData = { }; }
    else
      imported;
in
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"

    # let the compiler module do its own evalNetwork internally
    inputs.nixos-network-compiler.nixosModules.default

    ./host-network.nix
    ./mount-utils.nix
    ./container-settings.nix
    ./debugging-packages.nix
    ./sops.nix
  ];

  _module.args.fabricInputs = fabricInputs;
}

