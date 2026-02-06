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
    ./overwrites.nix
    ./mount-utils.nix
    #./host
    ./container-settings.nix
  ];
}
