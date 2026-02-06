{
  outPath,
  lib,
  config,
  ...
}:
{
  imports = [
    #"${outPath}/library/10-vms/nixos-shell-vm/host-config"
    ./host-config
    ./mount-utils.nix
    #./host
    ./container-settings.nix
  ];
}
