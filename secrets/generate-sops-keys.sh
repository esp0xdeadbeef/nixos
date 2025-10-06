#!/usr/bin/env bash
set -euo pipefail

# safe-setup-sops-age.sh
# Creates SSH ed25519 key (if missing), generates ssh-to-age identity (if missing),
# copies safe copies to /persist$HOME, prints the YAML anchor line.
#
# It will NOT modify .sops.yaml. It will not overwrite existing keys without backing up.
#
# Usage: ./safe-setup-sops-age.sh

HOME_DIR="${HOME}"
SSH_PRIV_KEY="${HOME_DIR}/.ssh/id_ed25519"
SOPS_AGE_DIR="${HOME_DIR}/.config/sops/age"
AGE_KEYS_FILE="${SOPS_AGE_DIR}/keys.txt"
PERSIST_ROOT="/persist${HOME_DIR}"
PERSIST_SOPS_AGE_DIR="${PERSIST_ROOT}/.config/sops/age"
PERSIST_SSH_DIR="${PERSIST_ROOT}/.ssh"
SOPS_YAML="./.sops.yaml"

mkdir -p "$HOME_DIR/.ssh" "$SOPS_AGE_DIR" "$PERSIST_SOPS_AGE_DIR" "$PERSIST_SSH_DIR"

echo "[info] starting safe sops/age bootstrap"

# 1) create SSH key only if missing
if [ -f "$SSH_PRIV_KEY" ]; then
  echo "[info] SSH key exists: $SSH_PRIV_KEY (not overwriting)"
else
  echo "[info] creating SSH key: $SSH_PRIV_KEY"
  ssh-keygen -t ed25519 -N "" -f "$SSH_PRIV_KEY" -q
  chmod 600 "$SSH_PRIV_KEY"
  chmod 644 "${SSH_PRIV_KEY}.pub"
  echo "[ok] ssh key created"
fi

# 2) produce age identity only if missing
if [ -f "$AGE_KEYS_FILE" ]; then
  echo "[info] age identity already exists: $AGE_KEYS_FILE (not regenerating)"
else
  echo "[info] generating age identity from SSH private key using ssh-to-age (nix-shell)"
  # if ssh-to-age not available, nix-shell will provide it
  nix-shell -p ssh-to-age --run "ssh-to-age -private-key -i '$SSH_PRIV_KEY' > '$AGE_KEYS_FILE'"
  chmod 600 "$AGE_KEYS_FILE"
  echo "[ok] age identity created at $AGE_KEYS_FILE"
fi

# 3) derive public age key (age-keygen -y)
if ! command -v age-keygen >/dev/null 2>&1; then
  # use nix-shell to run age-keygen if not present
  AGE_PUB="$(nix-shell -p age --run "age-keygen -y '${AGE_KEYS_FILE}'")"
else
  AGE_PUB="$(age-keygen -y "$AGE_KEYS_FILE")"
fi

if [ -z "$AGE_PUB" ]; then
  echo "[error] failed to derive age public key"
  exit 1
fi

# canonical anchor name
anchor="$(hostname -s | tr '[:upper:]' '[:lower:]')-$(whoami)"
yaml_line="  - &${anchor} ${AGE_PUB}"

# 4) safety: if .sops.yaml exists and already contains this public key, exit clean
if [ -f "$SOPS_YAML" ]; then
  if grep -F -q "$AGE_PUB" "$SOPS_YAML"; then
    echo "[ok] public key already present in $SOPS_YAML; nothing to do"
    echo
    echo "YAML line (already present):"
    echo "$yaml_line"
    exit 0
  fi
fi

# 5) copy to /persist only when missing or different (create backup if different)
copy_and_backup_if_needed() {
  src="$1"
  dst="$2"
  if [ ! -f "$dst" ]; then
    echo "[info] copying $src -> $dst"
    cp -a "$src" "$dst"
    chmod 600 "$dst"
    return
  fi

  if cmp -s "$src" "$dst"; then
    echo "[info] $dst already identical (no-op)"
    return
  fi

  # different file: backup existing dst and copy
  ts="$(date +%Y%m%dT%H%M%S)"
  backup="${dst}.bak.${ts}"
  echo "[warn] $dst differs from $src; backing up $dst -> $backup and replacing"
  cp -a "$dst" "$backup"
  cp -a "$src" "$dst"
  chmod 600 "$dst"
}

copy_and_backup_if_needed "$AGE_KEYS_FILE" "${PERSIST_SOPS_AGE_DIR}/keys.txt"
copy_and_backup_if_needed "$SSH_PRIV_KEY" "${PERSIST_SSH_DIR}/id_ed25519"

echo
echo "===== YAML snippet (paste under 'keys:' in your .sops.yaml) ====="
echo "$yaml_line"
echo "================================================================="
echo
echo "[note] script did not change .sops.yaml or creation_rules. Review and paste the line above where appropriate."
echo "[info] done"
