{
  config,
  lib,
  pkgs,
  ...
}:
let
  normalUserNames = lib.attrNames (
    lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users
  );
in
{
  users.groups.libvirtd.members = normalUserNames;

  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };
}
