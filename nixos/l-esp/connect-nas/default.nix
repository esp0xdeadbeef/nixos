{ config, pkgs, lib, ... }:

let
  mountBin = "${pkgs.cifs-utils}/bin/mount.cifs";   # full path!

  mkScript = shareKey: name:
    pkgs.writeShellScript "mount-nas-${name}" ''
      set -e
      IP=$(cat ${config.sops.secrets."nas-ip".path})
      SHARE=$(cat ${config.sops.secrets."${shareKey}".path})
      USER=$(cat ${config.sops.secrets."nas-username".path})
      PASS=$(cat ${config.sops.secrets."nas-password".path})

      exec ${mountBin} //"$IP"/"$SHARE" /mnt/qnap/${name} \
          -o username="$USER",password="$PASS",uid=1000,gid=100,iocharset=utf8,vers=3.0
    '';

  privateScript = mkScript "nas-share-private" "private";
  publicScript  = mkScript "nas-share-public"  "public";
in
{
  # declare all secrets
  sops.secrets."nas-ip"            = {};
  sops.secrets."nas-username"      = {};
  sops.secrets."nas-password"      = {};
  sops.secrets."nas-share-private" = {};
  sops.secrets."nas-share-public"  = {};

  # dirs
  systemd.tmpfiles.rules = [
    "d /mnt/qnap/private 0755 root root -"
    "d /mnt/qnap/public  0755 root root -"
  ];

  environment.systemPackages = [ pkgs.cifs-utils ];

  # oneshot mount services
  systemd.services.mount-nas-private = {
    description = "Mount NAS Private share (on‑demand)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = privateScript;
      RemainAfterExit = true;
    };
  };

  systemd.services.mount-nas-public = {
    description = "Mount NAS Public share (on‑demand)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = publicScript;
      RemainAfterExit = true;
    };
  };

  # automounts that trigger them
  systemd.automounts = [
    { where = "/mnt/qnap/private"; wantedBy = [ "multi-user.target" ];
      automountConfig.TimeoutIdleSec = "600"; requires = [ "mount-nas-private.service" ]; }
    { where = "/mnt/qnap/public";  wantedBy = [ "multi-user.target" ];
      automountConfig.TimeoutIdleSec = "600"; requires = [ "mount-nas-public.service"  ]; }
  ];
}
