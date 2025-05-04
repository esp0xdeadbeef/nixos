{ config, pkgs, lib, ... }:

let
  # Common CIFS mount options with systemd automount
  automount_opts = lib.concatStringsSep "," [
    "x-systemd.automount"
    "noauto"
    "x-systemd.idle-timeout=600"
    "x-systemd.device-timeout=5s"
    "x-systemd.mount-timeout=5s"
  ];
in {
  # Ensure the CIFS mount helper is available
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Declare SOPS secrets so they can be referenced
  sops.secrets = {
    "nas-ip"            = {};
    "nas-username"      = {};
    "nas-password"      = {};
    "nas-share-public"  = {};
    "nas-share-private" = {};
  };

  # Generate credential files from SOPS secrets
  environment.etc = {
    "smb-secrets-private".text = lib.concatStringsSep "\n" [
      "username=${builtins.readFile config.sops.secrets.nas-username.path}"
      "password=${builtins.readFile config.sops.secrets.nas-password.path}"
    ];
    "smb-secrets-public".text = lib.concatStringsSep "\n" [
      "username=${builtins.readFile config.sops.secrets.nas-username.path}"
      "password=${builtins.readFile config.sops.secrets.nas-password.path}"
    ];
  };

  # Declarative CIFS mounts with systemd automount
  fileSystems = {
    # Private share
    "/mnt/nas/private" = {
      device = "//${builtins.readFile config.sops.secrets.nas-ip.path}/${builtins.readFile config.sops.secrets.nas-share-private.path}";
      fsType = "cifs";
      options = [ "${automount_opts},credentials=/etc/smb-secrets-private,uid=1000,gid=100,iocharset=utf8,vers=3.0" ];
    };

    # Public share
    "/mnt/nas/public" = {
      device = "//${builtins.readFile config.sops.secrets.nas-ip.path}/${builtins.readFile config.sops.secrets.nas-share-public.path}";
      fsType = "cifs";
      options = [ "${automount_opts},credentials=/etc/smb-secrets-public,uid=1000,gid=100,iocharset=utf8,vers=3.0" ];
    };
  };
}
