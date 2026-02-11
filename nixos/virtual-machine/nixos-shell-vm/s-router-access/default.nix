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
    ./host-config
    ./mount-utils.nix
    ./container-router-access/container-settings.nix
    ./debugging-packages.nix
    ./sops.nix
  ];

  _module.args.fabricInputs = fabricInputs;
}
