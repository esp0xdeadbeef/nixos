{ relativeRepo
, lib
, config
, vmRoot
, ...
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
    ./host-config
    ./mount-utils.nix
    ./sops.nix
    ./container-settings.nix
  ];
}
