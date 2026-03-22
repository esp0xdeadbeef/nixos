{
  outPath,
  lib,
  config,
  inputs,
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
  _module.args.fabricInputs = fabricInputs;

  imports = [
    ./host-config
    ./fabric-input-loader.nix
    ./mount-utils.nix
    ./container-settings.nix
    ./nftables.nix
    ./debugging-packages.nix
  ];

  networking.hostName = "s-router-policy-only";

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  system.stateVersion = "25.11";
}
