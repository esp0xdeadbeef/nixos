{ config, lib, mailboxSets ? null, name, pkgs, ... }:
let
  cfg = config.profiles.web.server;
  hostName = config.networking.hostName or name;
  networkAddressesUnit = cfg.networkAddress.unit;
  networkAddressesService = lib.removeSuffix ".service" networkAddressesUnit;
  nginxRuntimeConfigService = "${hostName}-nginx-runtime-config";
  nginxRuntimeConfigUnit = "${nginxRuntimeConfigService}.service";
  certMailUnit = "${hostName}-cert-mail.service";
  webpageSyncService = "${hostName}-webpage-sync";
  webpageSyncUnit = "${webpageSyncService}.service";
  webpageReloadService = "${hostName}-webpage-reload";
  webpageReloadUnit = "${webpageReloadService}.service";
  webpageService = "${hostName}-webpage";
  webpageUnit = "${webpageService}.service";
  webpageEnvService = "${hostName}-webpage-env";
  webpageEnvUnit = "${webpageEnvService}.service";

  runtimeRoot = cfg.runtimeRoot;
  mailTlsFullchainPath = cfg.tls.fullchainPath;
  mailTlsKeyPath = cfg.tls.keyPath;
  githubTokenPath = config.sops.secrets.${cfg.githubTokenSecretName}.path;
  webpageRepoUrl = cfg.source.repoUrl;
  webpageRepoBranch = cfg.source.branch;
  webpageSourceDir = cfg.source.checkoutDir;
  webpageRuntimeDir = cfg.runtime.appDir;
  webpageStateDir = cfg.runtime.stateDir;
  webpagePublicDir = "${webpageRuntimeDir}/${cfg.runtime.publicSubdir}";
  webpageRestartMarker = "${runtimeRoot}/webpage-restart-needed";
  webpageEnvDir = "${runtimeRoot}/webpage";
  webpageRenderedEnvPath = "${webpageEnvDir}/env";
  webpageHost = cfg.backend.host;
  webpagePort = cfg.backend.port;

  nginxHttpConfPath = config.sops.secrets.${cfg.secretNames.nginxHttpConf}.path;
  webContactEnvPath = config.sops.secrets.${cfg.secretNames.contactEnv}.path;
  webRedirectEnvPath = config.sops.secrets.${cfg.secretNames.redirectEnv}.path;
  nginxPreviewUsernamePath = config.sops.secrets.${cfg.secretNames.previewUsername}.path;
  nginxPreviewPasswordPath = config.sops.secrets.${cfg.secretNames.previewPassword}.path;
  nginxRuntimeDir = "${runtimeRoot}/nginx";
  nginxHtpasswdPath = "${nginxRuntimeDir}/htpasswd";
  nginxRenderedHttpConfPath = "${nginxRuntimeDir}/http.conf";
  nginxGeneratedMailboxConfPath = "${nginxRuntimeDir}/mailbox-domains.conf";
  emptyMailboxPathList = pkgs.writeText "${hostName}-empty-mailbox-env-paths" "";
  mailboxSetEnvPathsConfig =
    if mailboxSets == null then {
      pathList = emptyMailboxPathList;
      paths = [ ];
    } else
      mailboxSets.mkEnvPaths {
        inherit config lib pkgs;
        name = "${hostName}-web-mailbox-set-env-paths";
        secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
      };
  mailAccountEnvPathsConfig =
    if mailboxSets == null then {
      pathList = emptyMailboxPathList;
      paths = [ ];
    } else
      mailboxSets.mkEnvPaths {
        inherit config lib pkgs;
        name = "${hostName}-web-mail-account-env-paths";
        secretRefs = mailboxSets.mailAccountEnvSecretRefs;
      };
  mailboxSetEnvPaths = mailboxSetEnvPathsConfig.paths;
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailAccountEnvPaths = mailAccountEnvPathsConfig.paths;
  mailAccountEnvPathList = mailAccountEnvPathsConfig.pathList;
  webMailSecretEnvRefs =
    if mailboxSets == null then
      [ ]
    else
      mailboxSets.envSecretRefs;
  nginxSecurityHeaders = ''
    # Security headers for nginx-generated responses, including redirects and Basic Auth 401s.
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=(), browsing-topics=()" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    add_header Cross-Origin-Resource-Policy "same-origin" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    add_header X-XSS-Protection "0" always;
  '';

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  prepareNginxRuntime = pkgs.writeShellApplication {
    name = "${hostName}-prepare-nginx-runtime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.openssl
    ];
    text = ''
      set -euo pipefail

      raw_conf=${lib.escapeShellArg nginxHttpConfPath}
      contact_env=${lib.escapeShellArg webContactEnvPath}
      redirect_env=${lib.escapeShellArg webRedirectEnvPath}
      rendered_conf=${lib.escapeShellArg nginxRenderedHttpConfPath}
      generated_mailbox_conf=${lib.escapeShellArg nginxGeneratedMailboxConfPath}
      username_file=${lib.escapeShellArg nginxPreviewUsernamePath}
      password_file=${lib.escapeShellArg nginxPreviewPasswordPath}
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      tls_fullchain=${lib.escapeShellArg mailTlsFullchainPath}
      tls_key=${lib.escapeShellArg mailTlsKeyPath}
      nginx_dir=${lib.escapeShellArg nginxRuntimeDir}
      htpasswd=${lib.escapeShellArg nginxHtpasswdPath}
      webpage_upstream=${lib.escapeShellArg "http://${webpageHost}:${toString webpagePort}"}

      install -d -m 0750 -o nginx -g nginx "$nginx_dir"

      username="$(tr -d '\r\n' < "$username_file")"
      password="$(tr -d '\r\n' < "$password_file")"

      if [ -z "$username" ]; then
        echo "nginx preview username is empty" >&2
        exit 1
      fi

      case "$username" in
        *:*)
          echo "nginx preview username must not contain ':'" >&2
          exit 1
          ;;
      esac

      password_hash="$(printf '%s' "$password" | openssl passwd -apr1 -stdin)"
      unset password

      tmp="$(mktemp "$nginx_dir/htpasswd.XXXXXX")"
      printf '%s:%s\n' "$username" "$password_hash" > "$tmp"
      unset password_hash
      chown nginx:nginx "$tmp"
      chmod 0440 "$tmp"
      mv "$tmp" "$htpasswd"

      words() {
        local input="''${1:-}"
        printf '%s\n' "$input" | tr ',\t\r\n' ' '
      }

      redirect_domains=""
      if [ -r "$redirect_env" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$redirect_env"
        set +a
        redirect_domains="''${WEB_REDIRECT_DOMAINS:-}"
        unset WEB_REDIRECT_DOMAINS WEB_REDIRECT_TARGET_URL WEB_REDIRECT_STATUS
      fi

      validate_domain() {
        local domain="$1"

        case "$domain" in
          *[!A-Za-z0-9.-]* | .* | *..* | *.)
            echo "invalid nginx web domain: $domain" >&2
            exit 1
            ;;
        esac
      }

      site_domain="$(
        set -a
        # shellcheck disable=SC1090
        . "$contact_env"
        set +a
        printf '%s' "''${WEB_SITE_DOMAIN:-}"
      )"
      site_domain="''${site_domain,,}"
      if [ -n "$site_domain" ]; then
        validate_domain "$site_domain"
      fi

      raw_has_server_name() {
        local name="$1"

        awk -v name="$name" '
          /^[[:space:]]*server_name[[:space:]]/ {
            for (i = 2; i <= NF; i++) {
              value = $i
              gsub(/;$/, "", value)
              if (value == name) {
                found = 1
              }
            }
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$raw_conf"
      }

      redirect_manages_domain() {
        local name="$1"
        local redirect_domain

        for redirect_domain in $(words "$redirect_domains"); do
          [ "$redirect_domain" = "$name" ] && return 0
        done

        return 1
      }

      generated_domain_names=()

      generated_domain_exists() {
        local name="$1"
        local generated_domain

        for generated_domain in "''${generated_domain_names[@]}"; do
          [ "$generated_domain" = "$name" ] && return 0
        done

        return 1
      }

      remember_generated_domains() {
        local name

        for name in "$@"; do
          generated_domain_names+=("$name")
        done
      }

      emit_preview_auth_map() {
        cat <<NGINX
      map "\$scheme:\$host" \$managed_web_preview_realm {
        default \$managed_web_preview_path_realm;
      }
      NGINX
      }

      emit_logo_preview_proxy_locations() {
        cat <<NGINX
        location = /__preview/logo-inspectie {
          proxy_pass $webpage_upstream;
          proxy_read_timeout 180s;
          proxy_send_timeout 180s;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location ^~ /__preview/logo-inspectie/ {
          proxy_pass $webpage_upstream;
          proxy_read_timeout 180s;
          proxy_send_timeout 180s;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
        }
      NGINX
      }

      emit_logo_preview_not_found_locations() {
        cat <<'NGINX'
        location = /__preview/logo-inspectie {
          return 404;
        }

        location ^~ /__preview/logo-inspectie/ {
          return 404;
        }
      NGINX
      }

      emit_logo_preview_locations_for_domain() {
        local domain="$1"

        if [ -n "$site_domain" ] && [ "$domain" = "$site_domain" ]; then
          emit_logo_preview_proxy_locations
        else
          emit_logo_preview_not_found_locations
        fi
      }

      emit_web_domain() {
        local domain="$1"
        local www_domain="$2"

        cat <<NGINX

      server {
        listen 80;
        listen [::]:80;
        server_name $domain $www_domain;

        location / {
          root /var/empty;
          try_files /__managed_web_redirect_never_exists @managed_web_redirect;
        }

        location @managed_web_redirect {
          return 301 https://$domain\$request_uri;
        }
      }

      server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name $domain;
        ssl_certificate $tls_fullchain;
        ssl_certificate_key $tls_key;

      NGINX
        emit_logo_preview_locations_for_domain "$domain"
        cat <<NGINX

        location / {
          proxy_pass $webpage_upstream;
          proxy_read_timeout 180s;
          proxy_send_timeout 180s;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
        }

      }

      server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name $www_domain;
        ssl_certificate $tls_fullchain;
        ssl_certificate_key $tls_key;

      NGINX
        emit_logo_preview_not_found_locations
        cat <<NGINX

        location / {
          root /var/empty;
          try_files /__managed_web_redirect_never_exists @managed_web_redirect;
        }

        location @managed_web_redirect {
          return 301 https://$domain\$request_uri;
        }
      }
      NGINX
      }

      emit_mail_redirect() {
        local mail_host="$1"
        local target_domain="$2"

        cat <<NGINX

      server {
        listen 80;
        listen [::]:80;
        server_name $mail_host;

        location / {
          root /var/empty;
          try_files /__managed_web_redirect_never_exists @managed_web_redirect;
        }

        location @managed_web_redirect {
          return 301 https://$target_domain\$request_uri;
        }
      }

      server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name $mail_host;
        ssl_certificate $tls_fullchain;
        ssl_certificate_key $tls_key;

      NGINX
        emit_logo_preview_not_found_locations
        cat <<NGINX

        location / {
          root /var/empty;
          try_files /__managed_web_redirect_never_exists @managed_web_redirect;
        }

        location @managed_web_redirect {
          return 301 https://$target_domain\$request_uri;
        }
      }
      NGINX
      }

      emit_proxy_domain() {
        local domain="$1"

        cat <<NGINX

      server {
        listen 80;
        listen [::]:80;
        server_name $domain;

        location / {
          root /var/empty;
          try_files /__managed_web_redirect_never_exists @managed_web_redirect;
        }

        location @managed_web_redirect {
          return 301 https://$domain\$request_uri;
        }
      }

      server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name $domain;
        ssl_certificate $tls_fullchain;
        ssl_certificate_key $tls_key;

      NGINX
        emit_logo_preview_locations_for_domain "$domain"
        cat <<NGINX

        location / {
          proxy_pass $webpage_upstream;
          proxy_read_timeout 180s;
          proxy_send_timeout 180s;
          proxy_set_header Host \$host;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
        }
      }
      NGINX
      }

      tmp_generated="$(mktemp "$nginx_dir/mailbox-domains.conf.XXXXXX")"
      {
        printf '# Generated from mailbox profile secrets. Raw nginx config takes precedence.\n'

        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          mailbox_set_path="''${entry#*=}"
          [ -r "$mailbox_set_path" ] || continue

          unset MAILBOX_DOMAIN MAILBOX_MAIL_HOST
          set -a
          # shellcheck disable=SC1090
          . "$mailbox_set_path"
          set +a

          domain="''${MAILBOX_DOMAIN:-}"
          [ -n "$domain" ] || continue
          validate_domain "$domain"

          www_domain="www.$domain"
          validate_domain "$www_domain"

          if ! redirect_manages_domain "$domain" \
            && ! redirect_manages_domain "$www_domain" \
            && ! raw_has_server_name "$domain" \
            && ! raw_has_server_name "$www_domain"; then
            emit_web_domain "$domain" "$www_domain"
            remember_generated_domains "$domain" "$www_domain"
          fi

          mail_host="''${MAILBOX_MAIL_HOST:-mail.$domain}"
          [ -n "$mail_host" ] || continue
          validate_domain "$mail_host"
          if [ "$mail_host" != "$domain" ] \
            && [ "$mail_host" != "$www_domain" ] \
            && ! redirect_manages_domain "$mail_host" \
            && ! raw_has_server_name "$mail_host"; then
            emit_mail_redirect "$mail_host" "$domain"
            remember_generated_domains "$mail_host"
          fi
        done < "$mailbox_set_env_path_list"

        for redirect_domain in $(words "$redirect_domains"); do
          [ -n "$redirect_domain" ] || continue
          validate_domain "$redirect_domain"

          if ! raw_has_server_name "$redirect_domain" \
            && ! generated_domain_exists "$redirect_domain"; then
            emit_proxy_domain "$redirect_domain"
            remember_generated_domains "$redirect_domain"
          fi
        done
      } > "$tmp_generated"
      chown nginx:nginx "$tmp_generated"
      chmod 0440 "$tmp_generated"
      mv "$tmp_generated" "$generated_mailbox_conf"

      tmp_conf="$(mktemp "$nginx_dir/http.conf.XXXXXX")"
      {
        cat <<'NGINX_SECURITY_HEADERS'
      ${nginxSecurityHeaders}
      NGINX_SECURITY_HEADERS
        emit_preview_auth_map
        cat "$raw_conf"
        cat "$generated_mailbox_conf"
      } > "$tmp_conf"
      chown nginx:nginx "$tmp_conf"
      chmod 0440 "$tmp_conf"
      mv "$tmp_conf" "$rendered_conf"

      awk '
        /^[[:space:]]*ssl_certificate(_key)?[[:space:]]+/ {
          path = $2
          gsub(/;$/, "", path)
          gsub(/^"/, "", path)
          gsub(/"$/, "", path)
          if (path !~ /^\$/) {
            print path
          }
        }
      ' "$raw_conf" | while IFS= read -r cert_path; do
        [ -n "$cert_path" ] || continue
        [ -e "$cert_path" ] || continue

        cert_dir="$(dirname "$cert_path")"
        chown root:nginx "$cert_dir" "$cert_path"
        chmod 0750 "$cert_dir"
        chmod 0640 "$cert_path"
      done
    '';
  };

  renderWebpageEnvironment = pkgs.writeShellApplication {
    name = "${hostName}-render-webpage-environment";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
    ];
    text = ''
      set -euo pipefail

      base_env=${lib.escapeShellArg webContactEnvPath}
      redirect_env=${lib.escapeShellArg webRedirectEnvPath}
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
      runtime_dir=${lib.escapeShellArg webpageEnvDir}
      rendered_env=${lib.escapeShellArg webpageRenderedEnvPath}
      public_dir=${lib.escapeShellArg webpagePublicDir}

      install -d -m 0750 -o nginx -g nginx "$runtime_dir"

      set -a
      # shellcheck source=/dev/null
      . "$base_env"
      # shellcheck source=/dev/null
      . "$redirect_env"
      set +a

      declare -A account_path_by_id
      declare -A account_domain_by_id
      declare -A account_smtp_host_by_id
      declare -A account_smtp_port_by_id
      declare -A account_domain_by_context
      declare -A account_smtp_host_by_context
      declare -A account_smtp_port_by_context

      words() {
        local raw="''${1//,/ }"
        raw="''${raw//;/ }"
        local word
        for word in $raw; do
          printf '%s\n' "$word"
        done
      }

      env_flag() {
        local value="''${!1:-}"
        case "''${value,,}" in
          1|true|yes|on)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      }

      secret_id_from_name() {
        local secret_name="$1"
        secret_name="''${secret_name%/env}"
        printf '%s\n' "''${secret_name##*/}"
      }

      load_account_env() {
        local account_path="$1"
        local field

        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER LABEL DISPLAY_NAME FROM SOURCE OUTGOING ADDRESS USERNAME IMAP_HOST SMTP_HOST MAIL_HOST IMAP_PORT SMTP_PORT; do
          unset "MAIL_ACCOUNT_$field"
        done

        # shellcheck source=/dev/null
        . "$account_path"
      }

      load_account_context() {
        local account_id="$1"
        local mailbox_set_id="''${2:-}"
        local account_path="''${account_path_by_id[$account_id]:-}"
        local context_key

        [ -n "$account_path" ] || return 1
        [ -r "$account_path" ] || return 1

        load_account_env "$account_path"

        if [ -n "$mailbox_set_id" ]; then
          context_key="$mailbox_set_id/$account_id"
          account_domain="''${account_domain_by_context[$context_key]:-}"
          account_context_smtp_host="''${account_smtp_host_by_context[$context_key]:-}"
          account_context_smtp_port="''${account_smtp_port_by_context[$context_key]:-}"
        else
          account_domain="''${account_domain_by_id[$account_id]:-}"
          account_context_smtp_host="''${account_smtp_host_by_id[$account_id]:-}"
          account_context_smtp_port="''${account_smtp_port_by_id[$account_id]:-}"
        fi

        account_address="''${MAIL_ACCOUNT_ADDRESS:-}"
        if [ -z "$account_address" ] && [ -n "''${MAIL_ACCOUNT_LOCALPART:-}" ] && [ -n "$account_domain" ]; then
          account_address="''${MAIL_ACCOUNT_LOCALPART}@$account_domain"
        fi

        account_username="''${MAIL_ACCOUNT_USERNAME:-$account_address}"
        account_password="''${MAIL_ACCOUNT_PASSWORD:-}"
        account_smtp_host="''${MAIL_ACCOUNT_SMTP_HOST:-}"
        [ -n "$account_smtp_host" ] || account_smtp_host="''${MAIL_ACCOUNT_MAIL_HOST:-}"
        [ -n "$account_smtp_host" ] || account_smtp_host="$account_context_smtp_host"
        account_smtp_port="''${MAIL_ACCOUNT_SMTP_PORT:-}"
        [ -n "$account_smtp_port" ] || account_smtp_port="$account_context_smtp_port"

        [ -n "$account_address" ]
      }

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        secret_name="''${entry%%=*}"
        account_path="''${entry#*=}"
        account_id="$(secret_id_from_name "$secret_name")"
        account_path_by_id["$account_id"]="$account_path"
      done < "$mail_account_env_path_list"

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        secret_name="''${entry%%=*}"
        mailbox_set_path="''${entry#*=}"
        mailbox_set_id="$(secret_id_from_name "$secret_name")"
        [ -r "$mailbox_set_path" ] || continue

        unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS MAILBOX_MAIL_HOST MAILBOX_IMAP_HOST MAILBOX_SMTP_HOST MAILBOX_IMAP_PORT MAILBOX_SMTP_PORT
        # shellcheck source=/dev/null
        . "$mailbox_set_path"

        mailbox_smtp_host="''${MAILBOX_SMTP_HOST:-}"
        [ -n "$mailbox_smtp_host" ] || mailbox_smtp_host="''${MAILBOX_MAIL_HOST:-}"

        for account_id in $(words "''${MAILBOX_ACCOUNTS:-}"); do
          account_domain_by_id["$account_id"]="''${MAILBOX_DOMAIN:-}"
          account_smtp_host_by_id["$account_id"]="$mailbox_smtp_host"
          account_smtp_port_by_id["$account_id"]="''${MAILBOX_SMTP_PORT:-}"
          account_domain_by_context["$mailbox_set_id/$account_id"]="''${MAILBOX_DOMAIN:-}"
          account_smtp_host_by_context["$mailbox_set_id/$account_id"]="$mailbox_smtp_host"
          account_smtp_port_by_context["$mailbox_set_id/$account_id"]="''${MAILBOX_SMTP_PORT:-}"
        done
      done < "$mailbox_set_env_path_list"

      public_account="''${WEB_PUBLIC_CONTACT_ACCOUNT:-''${WEB_CONTACT_ACCOUNT:-}}"
      form_account="''${WEB_FORM_ACCOUNT:-''${WEB_CONTACT_ACCOUNT:-}}"
      public_mailbox_set="''${WEB_PUBLIC_CONTACT_MAILBOX_SET:-''${WEB_CONTACT_MAILBOX_SET:-}}"
      form_mailbox_set="''${WEB_FORM_MAILBOX_SET:-''${WEB_CONTACT_MAILBOX_SET:-}}"

      if [ -n "$public_account" ] && load_account_context "$public_account" "$public_mailbox_set"; then
        [ -n "''${WEB_CONTACT_EMAIL:-}" ] || WEB_CONTACT_EMAIL="$account_address"
        [ -n "''${WEB_SITE_DOMAIN:-}" ] || WEB_SITE_DOMAIN="$account_domain"
      fi

      if [ -n "$form_account" ] && load_account_context "$form_account" "$form_mailbox_set"; then
        [ -n "''${CONTACT_FROM:-}" ] || CONTACT_FROM="$account_address"
        [ -n "''${SMTP_HOST:-}" ] || SMTP_HOST="$account_smtp_host"
        [ -n "''${SMTP_PORT:-}" ] || SMTP_PORT="$account_smtp_port"

        if env_flag WEB_FORM_SMTP_AUTH_FROM_ACCOUNT; then
          [ -n "''${SMTP_USERNAME:-}" ] || SMTP_USERNAME="$account_username"
          [ -n "''${SMTP_PASSWORD:-}" ] || SMTP_PASSWORD="$account_password"
        fi
      fi

      [ -n "''${WEB_SITE_NAME:-}" ] || WEB_SITE_NAME="''${CONTACT_BRAND:-Website}"
      [ -n "''${CONTACT_BRAND:-}" ] || CONTACT_BRAND="$WEB_SITE_NAME"
      if [ -z "''${WEB_SITE_URL:-}" ] && [ -n "''${WEB_SITE_DOMAIN:-}" ]; then
        WEB_SITE_URL="https://$WEB_SITE_DOMAIN"
      fi
      if [ -n "''${WEB_SITE_URL:-}" ]; then
        # shellcheck disable=SC2034
        CONTACT_SITE_URL="$WEB_SITE_URL"
      fi
      [ -n "''${WEB_REDIRECT_TARGET_URL:-}" ] || WEB_REDIRECT_TARGET_URL="''${WEB_SITE_URL:-/}"

      append_word_unique() {
        local var_name="$1"
        local value="$2"
        local current word

        [ -n "$value" ] || return 0
        case "$value" in
          http://* | https://*)
            ;;
          *)
            return 0
            ;;
        esac

        current="''${!var_name:-}"
        for word in $(words "$current"); do
          [ "$word" = "$value" ] && return 0
        done

        if [ -n "$current" ]; then
          printf -v "$var_name" '%s %s' "$current" "$value"
        else
          printf -v "$var_name" '%s' "$value"
        fi
      }

      # shellcheck disable=SC2034
      WEB_REDIRECT_ALLOWED_TARGETS=""
      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        mailbox_set_path="''${entry#*=}"
        [ -r "$mailbox_set_path" ] || continue

        unset MAILBOX_DOMAIN
        # shellcheck source=/dev/null
        . "$mailbox_set_path"

        [ -n "''${MAILBOX_DOMAIN:-}" ] || continue
        append_word_unique WEB_REDIRECT_ALLOWED_TARGETS "https://$MAILBOX_DOMAIN"
        append_word_unique WEB_REDIRECT_ALLOWED_TARGETS "https://www.$MAILBOX_DOMAIN"
      done < "$mailbox_set_env_path_list"

      quote_env() {
        printf '%q' "$1"
      }

      emit_env() {
        local name="$1"
        local value="''${!name:-}"
        printf '%s=' "$name"
        quote_env "$value"
        printf '\n'
      }

      tmp="$(mktemp "$runtime_dir/env.XXXXXX")"
      cat "$base_env" > "$tmp"
      {
        printf '\n# Redirects rendered from web/redirects/env.\n'
        cat "$redirect_env"
      } >> "$tmp"
      {
        printf '\n# Derived from web/contact/env and generic mailbox secrets.\n'
        for name in \
          WEB_SITE_NAME \
          WEB_SITE_DOMAIN \
          WEB_SITE_URL \
          WEB_HOST_DEFAULT_PATHS \
          WEB_REDIRECT_DOMAINS \
          WEB_REDIRECT_ALLOWED_TARGETS \
          WEB_REDIRECT_STATUS \
          WEB_REDIRECT_TARGET_URL \
          WEB_CONTACT_EMAIL \
          CONTACT_BRAND \
          CONTACT_SITE_URL \
          CONTACT_FROM \
          SMTP_HOST \
          SMTP_PORT \
          SMTP_USERNAME \
          SMTP_PASSWORD
        do
          emit_env "$name"
        done
      } >> "$tmp"

      chown nginx:nginx "$tmp"
      chmod 0440 "$tmp"
      mv "$tmp" "$rendered_env"

      security_contact="''${WEB_SECURITY_CONTACT_EMAIL:-''${WEB_CONTACT_EMAIL:-}}"
      security_site_url="''${WEB_SECURITY_SITE_URL:-''${WEB_SITE_URL:-}}"
      if [ -n "$security_contact" ] && [ -n "$security_site_url" ]; then
        security_dir="$public_dir/.well-known"
        security_path="$security_dir/security.txt"
        security_legacy_path="$public_dir/security.txt"
        canonical="''${WEB_SECURITY_CANONICAL_URL:-''${security_site_url%/}/.well-known/security.txt}"
        expires="$(date -u -d "''${WEB_SECURITY_EXPIRES_AFTER:-+180 days}" '+%Y-%m-%dT%H:%M:%SZ')"

        install -d -m 0755 -o nginx -g nginx "$security_dir"
        tmp_security="$(mktemp "$security_dir/security.txt.XXXXXX")"
        {
          printf 'Contact: mailto:%s\n' "$security_contact"
          printf 'Expires: %s\n' "$expires"
          printf 'Preferred-Languages: nl, en\n'
          printf 'Canonical: %s\n' "$canonical"
        } > "$tmp_security"
        chown nginx:nginx "$tmp_security"
        chmod 0644 "$tmp_security"
        mv "$tmp_security" "$security_path"
        cp "$security_path" "$security_legacy_path"
        chown nginx:nginx "$security_legacy_path"
        chmod 0644 "$security_legacy_path"
      fi
    '';
  };

  syncWebpageSource = pkgs.writeShellApplication {
    name = "${hostName}-sync-webpage-source";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.nix
      pkgs.rsync
    ];
    text = ''
      set -euo pipefail

      repo_url=${lib.escapeShellArg webpageRepoUrl}
      repo_branch=${lib.escapeShellArg webpageRepoBranch}
      token_file=${lib.escapeShellArg githubTokenPath}
      src=${lib.escapeShellArg webpageSourceDir}
      dst=${lib.escapeShellArg webpageRuntimeDir}
      state=${lib.escapeShellArg webpageStateDir}
      restart_marker=${lib.escapeShellArg webpageRestartMarker}

      has_existing_app() {
        [ -f "$dst/run-server.py" ]
      }

      has_source_checkout() {
        [ -d "$src/.git" ] \
          && [ -f "$src/run-server.py" ] \
          && git -C "$src" rev-parse --verify HEAD >/dev/null 2>&1
      }

      handle_remote_sync_failure() {
        if has_existing_app; then
          echo "webpage sync failed; keeping existing runtime app in $dst" >&2
          exit 0
        fi

        if has_source_checkout; then
          echo "webpage remote sync failed; rebuilding runtime app from existing source checkout in $src" >&2
          git -C "$src" reset --hard HEAD
          git -C "$src" clean -fdx
          return 0
        fi

        echo "webpage sync failed and no existing runtime app or source checkout is available" >&2
        exit 1
      }

      require_source_checkout() {
        if has_source_checkout; then
          return 0
        fi

        if [ -f "$dst/run-server.py" ]; then
          echo "webpage source checkout is unavailable; keeping existing runtime app in $dst" >&2
          exit 0
        fi

        echo "webpage source checkout is unavailable and no existing runtime app is available in $dst" >&2
        exit 1
      }

      if [ ! -s "$token_file" ]; then
        echo "missing GitHub token for webpage sync: $token_file" >&2
        exit 1
      fi

      install -d -m 0755 -o root -g root "$(dirname "$src")"
      install -d -m 0755 -o nginx -g nginx "$dst"

      askpass="$(mktemp)"
      trap 'rm -f "$askpass"' EXIT
      cat > "$askpass" <<'EOF'
      #!/bin/sh
      case "$1" in
        *Username*) printf '%s\n' x-access-token ;;
        *Password*) tr -d '\r\n' < "$GITHUB_TOKEN_FILE" ;;
        *) printf '\n' ;;
      esac
      EOF
      chmod 0700 "$askpass"

      export GIT_ASKPASS="$askpass"
      export GIT_TERMINAL_PROMPT=0
      export GITHUB_TOKEN_FILE="$token_file"

      if [ -d "$src/.git" ]; then
        if git -C "$src" remote set-url origin "$repo_url" \
          && git -C "$src" fetch --depth=1 origin "$repo_branch" \
          && git -C "$src" checkout -B "$repo_branch" FETCH_HEAD \
          && git -C "$src" reset --hard FETCH_HEAD \
          && git -C "$src" clean -fdx; then
          :
        else
          handle_remote_sync_failure
        fi
      else
        tmp="$(mktemp -d "$(dirname "$src")/source.tmp.XXXXXX")"
        trap 'rm -f "$askpass"; rm -rf "$tmp"' EXIT
        if ! git clone --depth=1 --branch "$repo_branch" "$repo_url" "$tmp/repo"; then
          handle_remote_sync_failure
        fi
        rm -rf "$src"
        mv "$tmp/repo" "$src"
        rmdir "$tmp"
      fi

      require_source_checkout

      runtime_rev="$(cat "$dst/.source-rev" 2>/dev/null || true)"
      source_rev="$(git -C "$src" rev-parse HEAD)"

      if ! logo_preview_store_path="$(
        nix --extra-experimental-features 'nix-command flakes' build \
          --no-link \
          --print-out-paths \
          "$src#logo-preview-assets"
      )"; then
        if has_existing_app; then
          echo "Vue asset build failed; keeping existing runtime app in $dst" >&2
          exit 0
        fi
        echo "Vue asset build failed and no existing runtime app is available" >&2
        exit 1
      fi
      if [ ! -f "$logo_preview_store_path/index.html" ]; then
        echo "Vue asset output is missing index.html: $logo_preview_store_path" >&2
        exit 1
      fi

      generated_state="$state/generated-logo-directions"
      generation_logs_state="$state/logo-generation-logs"
      discussions_state="$state/logo-discussions"
      install -d -m 0755 -o nginx -g nginx "$state" "$generated_state"
      install -d -m 0700 -o nginx -g nginx "$generation_logs_state" "$discussions_state"

      migrate_runtime_data() {
        local old_path="$1"
        local state_path="$2"
        if [ -d "$old_path" ] && [ ! -L "$old_path" ]; then
          rsync -a "$old_path/" "$state_path/"
        fi
      }

      migrate_runtime_data "$dst/webpagina/generated-logo-directions" "$generated_state"
      migrate_runtime_data "$dst/var/logo-generation-logs" "$generation_logs_state"
      migrate_runtime_data "$dst/var/logo-discussions" "$discussions_state"
      chown -R nginx:nginx "$state"
      chmod 0755 "$state" "$generated_state"
      chmod 0700 "$generation_logs_state" "$discussions_state"

      chown -R root:root "$src"
      rsync -a --delete \
        --chown=nginx:nginx \
        --chmod=D755,F644 \
        --exclude='.git/' \
        --exclude='.env' \
        --exclude='.env.*' \
        --filter='protect .env' \
        --filter='protect .env.*' \
        --exclude='webpagina/generated-logo-directions/' \
        --exclude='var/logo-generation-logs/' \
        --exclude='var/logo-discussions/' \
        --filter='protect webpagina/.well-known/***' \
        --filter='protect webpagina/security.txt' \
        "$src/" "$dst/"

      install -d -m 0755 -o nginx -g nginx "$dst/preview/logo-inspectie"
      rm -rf "$dst/preview/logo-inspectie/dist"
      ln -s "$logo_preview_store_path" "$dst/preview/logo-inspectie/dist"
      chown -h nginx:nginx "$dst/preview/logo-inspectie/dist"

      install -d -m 0755 -o nginx -g nginx "$dst/webpagina" "$dst/var"
      rm -rf \
        "$dst/webpagina/generated-logo-directions" \
        "$dst/var/logo-generation-logs" \
        "$dst/var/logo-discussions"
      ln -s "$generated_state" "$dst/webpagina/generated-logo-directions"
      ln -s "$generation_logs_state" "$dst/var/logo-generation-logs"
      ln -s "$discussions_state" "$dst/var/logo-discussions"
      chown -h nginx:nginx \
        "$dst/webpagina/generated-logo-directions" \
        "$dst/var/logo-generation-logs" \
        "$dst/var/logo-discussions"

      chmod 0755 "$dst/run-server.py" "$dst/start-page.sh"

      printf '%s\n' "$source_rev" > "$dst/.source-rev"
      chown nginx:nginx "$dst/.source-rev"
      chmod 0644 "$dst/.source-rev"

      if [ "$source_rev" != "$runtime_rev" ]; then
        touch "$restart_marker"
      fi
    '';
  };

  reloadWebpageAfterSync = pkgs.writeShellApplication {
    name = "${hostName}-reload-webpage-after-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      marker=${lib.escapeShellArg webpageRestartMarker}

      [ -e "$marker" ] || exit 0
      rm -f "$marker"

      if systemctl --quiet is-active ${lib.escapeShellArg webpageUnit}; then
        systemctl restart ${lib.escapeShellArg webpageUnit}
      fi
    '';
  };
in
{
  options.profiles.web.server = {
    enable = lib.mkEnableOption "SOPS-backed nginx webpage server";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file containing web runtime secrets.";
    };

    runtimeRoot = lib.mkOption {
      type = lib.types.str;
      default = "/run/${config.networking.hostName}";
      description = "Runtime root for generated nginx and webpage files.";
    };

    githubTokenSecretName = lib.mkOption {
      type = lib.types.str;
      default = "gh-token";
      description = "SOPS secret name containing the GitHub token used for runtime source sync.";
    };

    source = {
      repoUrl = lib.mkOption {
        type = lib.types.str;
        description = "Git repository URL for the runtime webpage source.";
      };

      branch = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Git branch to sync at runtime.";
      };

      checkoutDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/source";
        description = "Persistent checkout directory for the webpage source.";
      };
    };

    runtime = {
      appDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/app";
        description = "Runtime directory copied from the webpage checkout.";
      };

      publicSubdir = lib.mkOption {
        type = lib.types.str;
        default = "webpagina";
        description = "Public web root subdirectory inside runtime.appDir.";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/persist/srv/www/state";
        description = "Persistent generated SVG, request-log, and discussion state outside runtime.appDir.";
      };
    };

    backend = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address the webpage backend listens on.";
      };

      port = lib.mkOption {
        type = lib.types.ints.between 1 65535;
        default = 8080;
        description = "Port the webpage backend listens on.";
      };

      corsAllowOrigin = lib.mkOption {
        type = lib.types.str;
        default = "*";
        description = "CORS_ALLOW_ORIGIN passed to the webpage backend.";
      };
    };

    networkAddress.unit = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}-network-addresses.service";
      description = "Systemd unit that renders or applies runtime network address data.";
    };

    tls = {
      fullchainPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "TLS fullchain path used by nginx generated virtual hosts.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "TLS private key path used by nginx generated virtual hosts.";
      };
    };

    secretNames = {
      nginxHttpConf = lib.mkOption {
        type = lib.types.str;
        default = "web/nginx/http_conf";
        description = "SOPS secret key containing additional nginx HTTP config.";
      };

      contactEnv = lib.mkOption {
        type = lib.types.str;
        default = "web/contact/env";
        description = "SOPS secret key containing webpage contact env.";
      };

      redirectEnv = lib.mkOption {
        type = lib.types.str;
        default = "web/redirects/env";
        description = "SOPS secret key containing webpage redirect env.";
      };

      previewUsername = lib.mkOption {
        type = lib.types.str;
        default = "web/preview/username";
        description = "SOPS secret key containing preview basic-auth username.";
      };

      previewPassword = lib.mkOption {
        type = lib.types.str;
        default = "web/preview/password";
        description = "SOPS secret key containing preview basic-auth password.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = mailboxSets != null;
        message = "profiles.web.server requires profiles.nixos.mail.mailbox-sets to be imported and enabled.";
      }
      {
        assertion = cfg.sopsFile != null;
        message = "profiles.web.server.sopsFile must be set.";
      }
      {
        assertion = cfg.source.repoUrl != "";
        message = "profiles.web.server.source.repoUrl must be set.";
      }
      {
        assertion = cfg.tls.fullchainPath != null && cfg.tls.keyPath != null;
        message = "profiles.web.server.tls.fullchainPath and keyPath must be set.";
      }
    ];

    sops.secrets =
      {
        ${cfg.secretNames.nginxHttpConf} = {
          sopsFile = cfg.sopsFile;
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };

        ${cfg.secretNames.contactEnv} = {
          sopsFile = cfg.sopsFile;
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
            webpageEnvUnit
            webpageUnit
          ];
        };

        ${cfg.secretNames.redirectEnv} = {
          sopsFile = cfg.sopsFile;
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
            webpageEnvUnit
            webpageUnit
          ];
        };

        ${cfg.secretNames.previewUsername} = {
          sopsFile = cfg.sopsFile;
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };

        ${cfg.secretNames.previewPassword} = {
          sopsFile = cfg.sopsFile;
          owner = "nginx";
          group = "nginx";
          mode = "0440";
          restartUnits = [
            nginxRuntimeConfigUnit
            "nginx.service"
          ];
        };
      }
      // builtins.listToAttrs (
        map
          (secret: {
            inherit (secret) name;
            value = {
              inherit (secret) key sopsFile;
              restartUnits = [
                certMailUnit
                nginxRuntimeConfigUnit
                "nginx.service"
                webpageEnvUnit
                webpageUnit
              ];
            };
          })
          webMailSecretEnvRefs
      );

    systemd.tmpfiles.rules = [
      "d ${runtimeRoot} 0755 root root -"
      "d ${nginxRuntimeDir} 0750 nginx nginx -"
      "d ${webpageEnvDir} 0750 nginx nginx -"
      "d /persist/srv 0755 root root -"
      "d /persist/srv/www 0755 root root -"
      "d ${webpageSourceDir} 0755 root root -"
      "d ${webpageRuntimeDir} 0755 nginx nginx -"
      "z /var/lib/acme 0755 root root -"
      "d /var/log/nginx 0750 nginx nginx -"
      "z /var/log/nginx 0750 nginx nginx -"
      "z /var/log/nginx/access.log 0640 nginx nginx -"
      "z /var/log/nginx/error.log 0640 nginx nginx -"
    ];

    systemd.services.${networkAddressesService}.before = [ "nginx.service" ];

    systemd.services.${nginxRuntimeConfigService} = {
      description = "Prepare ${hostName} nginx runtime files from SOPS";
      before = [ "nginx.service" ];
      requiredBy = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "5min";
      };
      preStart = waitForReadableFiles "nginx runtime" [
        nginxHttpConfPath
        nginxPreviewUsernamePath
        nginxPreviewPasswordPath
        webContactEnvPath
        webRedirectEnvPath
        mailTlsFullchainPath
        mailTlsKeyPath
      ] + waitForReadableFiles "nginx runtime mailbox sets" mailboxSetEnvPaths;
      script = "${lib.getExe prepareNginxRuntime}";
    };

    systemd.services.${webpageSyncService} = {
      description = "Sync ${hostName} webpage source from GitHub";
      after = [ "network-online.target" ];
      before = [ webpageUnit ];
      wants = [ "network-online.target" ];
      requiredBy = [ webpageUnit ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.OnSuccess = [ webpageReloadUnit ];
      serviceConfig = {
        Type = "oneshot";
      };
      preStart = waitForReadableFiles "webpage sync" [
        githubTokenPath
      ];
      script = "${lib.getExe syncWebpageSource}";
    };

    systemd.services.${webpageReloadService} = {
      description = "Reload ${hostName} webpage after source sync";
      after = [ webpageSyncUnit ];
      serviceConfig.Type = "oneshot";
      script = "${lib.getExe reloadWebpageAfterSync}";
    };

    systemd.services.${webpageEnvService} = {
      description = "Prepare ${hostName} webpage environment from SOPS";
      before = [ webpageUnit ];
      requiredBy = [ webpageUnit ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "2min";
      };
      preStart = waitForReadableFiles "webpage env" (
        [
          webContactEnvPath
          webRedirectEnvPath
        ]
        ++ mailboxSetEnvPaths
        ++ mailAccountEnvPaths
      );
      script = "${lib.getExe renderWebpageEnvironment}";
    };

    systemd.timers.${webpageSyncService} = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
        AccuracySec = "1min";
        Persistent = true;
      };
    };

    systemd.services.${webpageService} = {
      description = "Run ${hostName} webpage backend";
      after = [
        "network.target"
        webpageSyncUnit
        webpageEnvUnit
      ];
      requires = [
        webpageSyncUnit
        webpageEnvUnit
      ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HOST = webpageHost;
        PORT = toString webpagePort;
        WEB_ROOT = "webpagina";
        CORS_ALLOW_ORIGIN = cfg.backend.corsAllowOrigin;
      };
      path = [ pkgs.python3 ];
      serviceConfig = {
        User = "nginx";
        Group = "nginx";
        WorkingDirectory = webpageRuntimeDir;
        EnvironmentFile = webpageRenderedEnvPath;
        ExecStart = "${pkgs.python3}/bin/python3 ./run-server.py";
        Restart = "always";
        RestartSec = "5s";
      };
      preStart = waitForReadableFiles "web contact" [
        webpageRenderedEnvPath
      ];
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      appendHttpConfig = ''
        log_format managed_web_host_combined '$remote_addr host=$host server=$server_name '
          'request="$request" status=$status bytes=$body_bytes_sent '
          'location="$sent_http_location" auth="$sent_http_www_authenticate" '
          'referer="$http_referer" user_agent="$http_user_agent"';
        access_log /var/log/nginx/access.log managed_web_host_combined;

        map $uri $managed_web_preview_path_realm {
          default "preview";
          /.well-known/security.txt off;
          /security.txt off;
        }

        auth_basic $managed_web_preview_realm;
        auth_basic_user_file ${nginxHtpasswdPath};

        include ${nginxRenderedHttpConfPath};
      '';
    };

    systemd.services.nginx = {
      after = [
        networkAddressesUnit
        nginxRuntimeConfigUnit
        webpageUnit
      ];
      requires = [
        networkAddressesUnit
        nginxRuntimeConfigUnit
        webpageUnit
      ];
      preStart = lib.mkBefore (waitForReadableFiles "nginx" [
        nginxRenderedHttpConfPath
        nginxGeneratedMailboxConfPath
        nginxHtpasswdPath
      ]);
      serviceConfig.TimeoutStartSec = "5min";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
