{
  outPath,
  lib,
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

  inventoryImported = import ../inventory.nix;

  globalInventory =
    if builtins.isFunction inventoryImported then
      inventoryImported { inherit lib; }
    else
      inventoryImported;
in
{
  _module.args = {
    inherit fabricInputs globalInventory;
  };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    ./fabric-input-loader.nix
    ./host-network
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
  ];
}
