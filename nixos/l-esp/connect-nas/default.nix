{
  config,
  pkgs,
  lib,
  ...
}:

let

  automount_opts = lib.concatStringsSep "," [
    "x-systemd.automount"
    "noauto"
    "x-systemd.idle-timeout=60"
    "x-systemd.device-timeout=5s"
    "x-systemd.mount-timeout=5s"
    "x-systemd.requires=network-online.target"
  ];
in
{

  environment.systemPackages = [ pkgs.cifs-utils ];

  sops.secrets = {
    "nas-ip" = { };
    "nas-username" = { };
    "nas-password" = { };
    "nas-share-public" = { };
    "nas-share-private" = { };
  };

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

  fileSystems = {

    "/mnt/nas/private" = {
      device = "//${builtins.readFile config.sops.secrets.nas-ip.path}/${builtins.readFile config.sops.secrets.nas-share-private.path}";
      fsType = "cifs";
      options = [
        "${automount_opts},credentials=/etc/smb-secrets-private,uid=1000,gid=100,iocharset=utf8,vers=3.0"
      ];
    };

    "/mnt/nas/public" = {
      device = "//${builtins.readFile config.sops.secrets.nas-ip.path}/${builtins.readFile config.sops.secrets.nas-share-public.path}";
      fsType = "cifs";
      options = [
        "${automount_opts},credentials=/etc/smb-secrets-public,uid=1000,gid=100,iocharset=utf8,vers=3.0"
      ];
    };
  };
}
