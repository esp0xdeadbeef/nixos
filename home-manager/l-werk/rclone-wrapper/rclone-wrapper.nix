{ config, pkgs, ... }:

let
  seedFile = "${config.home.homeDirectory}/.config/rclone/password_seed";

  rcloneWrapper = pkgs.writeShellScriptBin "rclone-crypt" ''
    set -euo pipefail

    SEED_FILE="${seedFile}"
    SEED=$(<"$SEED_FILE")

    TMP_CONF="$(mktemp)"
    TMP_AUTH="$(mktemp)"

    echo "[*] Deriving password from sops-managed seed..."
    CRYPT_PASS=$(echo -n "$SEED" | ${pkgs.coreutils}/bin/sha256sum | cut -d ' ' -f 1)
    CRYPT_OBS=$(${pkgs.rclone}/bin/rclone obscure "$CRYPT_PASS")
    SALT_OBS=$(${pkgs.rclone}/bin/rclone obscure "static-salt")

    echo "[*] Launching browser for OneDrive auth..."
    ${pkgs.rclone}/bin/rclone authorize onedrive --output-file "$TMP_AUTH"
    TOKEN=$(${pkgs.jq}/bin/jq -c '.' < "$TMP_AUTH")

    echo -n "Enter your drive_id: "
    read DRIVE_ID

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

    rm -f "$TMP_CONF" "$TMP_AUTH"
  '';
in
{
  sops.secrets.rclone-password.path = seedFile;

  home.packages = [ rcloneWrapper ];
}
