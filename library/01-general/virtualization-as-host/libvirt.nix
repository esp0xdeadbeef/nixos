{ config, lib, pkgs, ... }:
{
  users.users.deadbeef = {
    extraGroups = [ "libvirtd" ];
  };

  virtualisation.libvirtd = {
    enable = true;

    extraConfig = ''
      secrets_encryption_key = "/persist/var/lib/libvirt/secrets/secrets-encryption-key"
    '';

    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  systemd.services.libvirtd.serviceConfig = {
    LoadCredentialEncrypted = lib.mkForce [ ];
  };
}
