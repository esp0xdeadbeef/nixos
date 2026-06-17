{
  config,
  lib,
  pkgs,
  ...
}:
let
  primaryUser = config.local.users.primary.resolvedName;
in
{
  virtualisation.spiceUSBRedirection.enable = true;
  virtualisation.docker.enable = true;
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = lib.mkIf (primaryUser != null) [ primaryUser ];

  # boot.binfmt.emulatedSystems = [
  #   "aarch64-linux"
  #   "riscv64-linux"
  # ];
}
