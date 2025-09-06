{ config, pkgs, lib, ... }:

let
  scriptPath = "${config.home.homeDirectory}/.local/bin/rclone-crypt";
in
{
  sops.secrets.rclone-password = {};
  sops.secrets.rclone-drive_id = {};

  home.activation.installRcloneWrapper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    echo "[*] Writing rclone-crypt wrapper to ${scriptPath}"
    install -Dm755 /dev/stdin ${scriptPath} <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SEED="$(<${config.sops.secrets."rclone-password".path})"
DRIVE_ID="$(<${config.sops.secrets."rclone-drive_id".path})"

TMP_CONF="$(mktemp)"
TOKEN_PATH="$HOME/Documents/.rclone-auth-$USER.json"

echo "[*] Deriving password from sops-managed seed..."
CRYPT_PASS=$(echo -n "$SEED" | sha256sum | cut -d ' ' -f 1)
CRYPT_OBS=$(rclone obscure "$CRYPT_PASS")
SALT_OBS=$(rclone obscure "static-salt")

if [[ -f "$TOKEN_PATH" ]]; then
  EXPIRY=$(jq -r '.expiry' "$TOKEN_PATH")
  NOW=$(date --iso-8601=seconds)
  if [[ "$EXPIRY" > "$NOW" ]]; then
    echo "[*] Reusing cached OneDrive token..."
    TOKEN=$(cat "$TOKEN_PATH")
  else
    echo "[*] Token expired. Reauthenticating..."
    rclone authorize onedrive | grep -v Paste -i > "$TOKEN_PATH"
    chmod 600 "$TOKEN_PATH"
    TOKEN=$(cat "$TOKEN_PATH")
  fi
else
  echo "[*] No token found. Starting authentication..."
  rclone authorize onedrive | grep -v Paste -i > "$TOKEN_PATH"
  chmod 600 "$TOKEN_PATH"
  TOKEN=$(cat "$TOKEN_PATH")
fi

cat > "$TMP_CONF" <<RCLONECONF
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
RCLONECONF

echo "[*] Running rclone with temporary config..."
rclone --config "$TMP_CONF" "$@"
rm -f "$TMP_CONF"
EOF
  '';

  home.packages = with pkgs; [
    rclone
    jq
    coreutils
  ];
}
