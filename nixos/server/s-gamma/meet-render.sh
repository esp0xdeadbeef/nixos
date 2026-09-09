#!/usr/bin/env bash
# Render the s-gamma meet (Galene) nginx reverse-proxy server block at
# runtime from the SOPS-managed meet/hostname secret. The public hostname
# is read here, never committed to the repository.
set -euo pipefail

hostname_file="${MEET_HOSTNAME_FILE:?}"
group_file="${MEET_GROUP_FILE:?}"
nginx_conf="${MEET_NGINX_CONF:?}"
groups_dir="${MEET_GROUPS_DIR:?}"
data_dir="${MEET_DATA_DIR:?}"
mail_fullchain="${MEET_MAIL_FULLCHAIN:?}"
mail_key="${MEET_MAIL_KEY:?}"

hostname="$(tr -d '\r\n' < "$hostname_file")"

# Always leave a valid (possibly empty) nginx include before validating, so
# a failed render never leaves nginx with a dangling include path.
install -d -m 0750 -o nginx -g nginx "$(dirname "$nginx_conf")"
: > "$nginx_conf"

case "$hostname" in
  '' | *[!A-Za-z0-9.-]* | .* | *..* | *.)
    echo "invalid meet hostname" >&2
    exit 1
    ;;
esac

# Write the group definition (admin credentials) from SOPS into the
# persisted groups directory. Galene reloads groups from this directory.
install -d -m 0750 -o galene -g galene "$groups_dir"
install -m 0640 -o galene -g galene "$group_file" "$groups_dir/main.json"

# Tell Galene the public URL clients use, so it advertises wss:// (not the
# loopback ws:// it would otherwise derive from running -insecure behind
# the TLS-terminating reverse proxy).
install -d -m 0750 -o galene -g galene "$data_dir"
cat > "$data_dir/config.json" <<EOF
{"proxyURL": "https://${hostname}/"}
EOF
chown galene:galene "$data_dir/config.json"

cat > "$nginx_conf" <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${hostname};
  location /.well-known/acme-challenge/ { root /var/lib/acme/acme-challenge; }
  location / { return 301 https://\$host\$request_uri; }
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name ${hostname};

  ssl_certificate ${mail_fullchain};
  ssl_certificate_key ${mail_key};

  # Allow the camera and microphone for this origin; the browser blocks
  # getUserMedia without an explicit Permissions-Policy grant.
  add_header Permissions-Policy "camera=(self), microphone=(self)" always;

  # Dedicated websocket endpoint (Galene listens on /ws), and a plain
  # reverse proxy for the rest. Matches Galene's documented nginx setup.
  location /ws {
    proxy_pass http://127.0.0.1:8443/ws;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header Host \$http_host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 86400;
  }

  location / {
    proxy_pass http://127.0.0.1:8443;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
  }
}
EOF
