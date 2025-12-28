{
  config,
  pkgs,
  lib,
  sops,
  ...
}:

{
  environment.systemPackages = [ pkgs.cifs-utils ];

  sops.secrets = {
    "nas-ip" = { };
    "nas-username" = { };
    "nas-password" = { };
    "nas-share-private" = { };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/nas 0755 root root -"
    "d /mnt/nas/private 0755 root root -"
  ];

  systemd.services.generate-nas-units = {
    description = "Generate NAS automount units from SOPS secrets";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.systemd
      pkgs.cifs-utils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "generate-nas-automounts" ''
        set -euo pipefail
        echo "[generate-nas-units] Reading secrets and generating units..."

        read_secret() { tr -d '\r\n' < "$1"; }

        host="$(read_secret '${config.sops.secrets."nas-ip".path}')"
        user="$(read_secret '${config.sops.secrets."nas-username".path}')"
        pass="$(read_secret '${config.sops.secrets."nas-password".path}')"
        sharePrivate="$(read_secret '${config.sops.secrets."nas-share-private".path}')"

        credfile="/run/nas.creds"
        umask 077
        printf 'username=%s\npassword=%s\n' "$user" "$pass" > "$credfile"
        chmod 600 "$credfile"

        mkdir -p /mnt/nas/private

        for name in private; do
          share=$([ "$name" = public ] && echo "$sharePublic" || echo "$sharePrivate")
          cat > /run/systemd/system/mnt-nas-$name.mount <<EOF
        [Unit]
        Description=SMB mount ($name)
        After=network-online.target
        ConditionPathExists=$credfile

        [Mount]
        What=//$host/$share
        Where=/mnt/nas/$name
        Type=cifs
        Options=credentials=$credfile,vers=3.0,sec=ntlmssp,noserverino,iocharset=utf8,uid=1000,gid=100,file_mode=0755,dir_mode=0755
        EOF

                  cat > /run/systemd/system/mnt-nas-$name.automount <<EOF
        [Unit]
        Description=Automount SMB ($name)
        After=network-online.target

        [Automount]
        Where=/mnt/nas/$name
        TimeoutIdleSec=60

        [Install]
        WantedBy=multi-user.target
        EOF
        done

        systemctl daemon-reload
        systemctl start mnt-nas-private.automount
        echo "[generate-nas-units] Automounts active."
      '';
    };
  };
}
