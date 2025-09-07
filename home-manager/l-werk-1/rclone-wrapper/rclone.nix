{ config, lib, pkgs, sopsSecrets, ... }:

let
  rcloneWrapper = pkgs.writeShellScriptBin "rclone-crypt" ''
    set -euo pipefail

    SEED=$(cat ${config.sops.secrets."rclone-password".path})
    DRIVE_ID=$(cat ${config.sops.secrets."rclone-drive_id".path})

    TMP_CONF="$(mktemp)"
    TOKEN_PATH="$HOME/Documents/.rclone-auth-$USER.json"

    echo "[*] Deriving password from sops-managed seed..."
    CRYPT_PASS=$(echo -n "$SEED" | ${pkgs.coreutils}/bin/sha256sum | cut -d ' ' -f 1)
    CRYPT_OBS=$(${pkgs.rclone}/bin/rclone obscure "$CRYPT_PASS")
    SALT_OBS=$(${pkgs.rclone}/bin/rclone obscure "static-salt")

    if [[ -f "$TOKEN_PATH" ]]; then
      EXPIRY=$(${pkgs.jq}/bin/jq -r '.expiry' "$TOKEN_PATH")
      NOW=$(${pkgs.coreutils}/bin/date --iso-8601=seconds)

      if [[ "$EXPIRY" > "$NOW" ]]; then
        echo "[*] Reusing cached OneDrive token..."
        TOKEN=$(cat "$TOKEN_PATH")
      else
        echo "[*] Token expired. Reauthenticating..."
        ${pkgs.rclone}/bin/rclone authorize onedrive | grep -v Paste -i > "$TOKEN_PATH"
        chmod 600 "$TOKEN_PATH"
        TOKEN=$(cat "$TOKEN_PATH")
      fi
    else
      echo "[*] No token found. Starting authentication..."
      ${pkgs.rclone}/bin/rclone authorize onedrive | grep -v Paste -i > "$TOKEN_PATH"
      chmod 600 "$TOKEN_PATH"
      TOKEN=$(cat "$TOKEN_PATH")
    fi

    cat > "$TMP_CONF" <<EOF
[rsync]
type = onedrive
token = $TOKEN
drive_id = $DRIVE_ID
drive_type = business

[crypt]
type = crypt
remote = rsync:/secure
filename_encryption = standard
directory_name_encryption = true
password = $CRYPT_OBS
password2 = $SALT_OBS
EOF

    echo "[*] Running rclone with temporary config..."
    ${pkgs.rclone}/bin/rclone --config "$TMP_CONF" "$@"

    rm -f "$TMP_CONF"
  '';

  backupScript = pkgs.writeShellScript "pentest-backup" ''
    set -euo pipefail

    echo "[*] Preparing directory and removing old folders..."
    mkdir -p /home/deadbeef/pentest
    cd /home/deadbeef/pentest

    for dir in *; do
      [ -d "$dir" ] || continue
      if [ "$(${pkgs.coreutils}/bin/stat -c %Y "$dir")" -lt "$(date -d '100 days ago' +%s)" ]; then
        echo "[*] Deleting: $dir"
        rm -rf -- "$dir"
      fi
    done
    echo "[*] Backing up ~/pentest to OneDrive..."
    ${rcloneWrapper}/bin/rclone-crypt sync --links --ignore-errors /home/deadbeef/pentest crypt:pentest-backup

    echo "[*] Backup + cleanup finished."
  '';
in {
  # SOPS secret declarations
  sops.secrets."rclone-password" = { };
  sops.secrets."rclone-drive_id" = { };

  # Expose wrapper so you can run it manually too
  home.packages = [ rcloneWrapper ];

  # Systemd service
  systemd.user.services.pentest-backup = {
    Unit = {
      Description = "Backup and cleanup of pentest directory";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${backupScript}";
    };
  };

  # Daily timer
  systemd.user.timers.pentest-backup = {
    Unit = {
      Description = "Daily timer for pentest backup + cleanup";
    };

    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
      AccuracySec = "15min";
      StartupDelaySec = "10min";
    };

    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
