{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/virtualization-as-host/general.nix"
    "${outPath}/library/01-general/virtualization-as-host/libvirt.nix"
    "${outPath}/library/01-general/virtualization-as-host/podman.nix"
    "${outPath}/library/01-general/virtualization-as-host/lxc.nix"
  ];
}
