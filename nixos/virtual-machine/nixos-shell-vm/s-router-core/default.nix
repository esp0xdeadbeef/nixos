{
  outPath,
  lib,
  config,
  vmRoot,
  ...
}:
let
  vmRoot =
    let
      file = __curPos.file;
    in
    builtins.dirOf file;
in
{
  _module.args.vmRoot = vmRoot;

  imports = [
    #"${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./host-config
    ./mount-utils.nix
    #./host
    ./sops.nix
    #./container-settings.nix
    ./container-edge-pppoe-transit.nix
  ];
}
