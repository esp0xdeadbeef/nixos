{
  outPath,
  lib,
  config,
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
    "${outPath}/library/10-vms/nixos-shell-vm/host-config"
    #./overwrites.nix
    ./mount-utils.nix
    #./host
    ./container-settings.nix

  ];
}
