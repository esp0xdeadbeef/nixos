{
  config,
  lib,
  pkgs,
  ...
}:
let
  primaryUser = config.local.users.primary.resolvedName;
in
lib.mkIf (primaryUser != null) {
  users.users.${primaryUser} = {
    extraGroups = [ "libvirtd" ];
  };

  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };
}
