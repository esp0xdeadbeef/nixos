{ outPath, ... }:
{
  imports = [
    "${outPath}/library/01-general/virtualization-as-host/libvirt.nix"
  ];

  programs.virt-manager.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
}
