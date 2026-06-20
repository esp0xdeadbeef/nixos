{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/virtualization-as-host/lxc.nix"
  ];
}
