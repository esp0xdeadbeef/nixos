{ inputs
, lib
, outPath
, ...
}:

let
  labSource = "active-lab";
in
{
  _module.args.sRouterTestClientsLabProfile = {
    inherit labSource;
    labSelector = "s-router-test-clients";
  };

  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    "${inputs.network-renderer-nixos}/s88/ControlModule/module/host-validation.nix"
    ./modules/host-composition.nix
  ];
}
