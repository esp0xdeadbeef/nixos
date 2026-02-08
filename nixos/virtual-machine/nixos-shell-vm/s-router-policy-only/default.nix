{
  outPath,
  lib,
  config,
  ...
}:
{
  imports = [
    "${outPath}/library/10-vms/nixos-shell-vm/host-config-router"
    ./mount-utils.nix
    ./container-settings.nix
  ];
}
