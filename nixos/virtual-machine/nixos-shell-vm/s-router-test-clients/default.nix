{ inputs
, outPath
, ...
}:

{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-routers-without-network"
    "${inputs.network-renderer-nixos}/s88/ControlModule/module/host-validation.nix"
    ./modules/host-composition.nix
    ./management-vlan2.nix
  ];
}
