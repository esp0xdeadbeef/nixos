{ config, lib, mailboxSets ? null, name, outPath, pkgs, ... }:
let
  hostName = name;
  networkAddressesService = "${hostName}-network-addresses";
  networkAddressesUnit = "${networkAddressesService}.service";
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
  runtimeSopsFile = outPath + "/secrets/s-gamma-runtime.yaml";

  runtimeRoot = "/run/${hostName}";
  githubTokenPath = config.sops.secrets.gh-token.path;
  webpageRepoUrl = "https://github.com/esp0xdeadbeef/www.git";
  webpageRepoBranch = "main";
  webpageSourceDir = "/persist/srv/www/source";
  webpageRuntimeDir = "/persist/srv/www/app";
  webpageRestartMarker = "${runtimeRoot}/webpage-restart-needed";
  webpageEnvDir = "${runtimeRoot}/webpage";
  webpageRenderedEnvPath = "${webpageEnvDir}/env";
  webpageHost = "127.0.0.1";
  webpagePort = 8080;

  nginxHttpConfPath = config.sops.secrets."web/nginx/http_conf".path;
  webContactEnvPath = config.sops.secrets."web/contact/env".path;
  nginxPreviewUsernamePath = config.sops.secrets."web/preview/username".path;
  nginxPreviewPasswordPath = config.sops.secrets."web/preview/password".path;
  nginxRuntimeDir = "${runtimeRoot}/nginx";
  nginxHtpasswdPath = "${nginxRuntimeDir}/htpasswd";
  nginxRenderedHttpConfPath = "${nginxRuntimeDir}/http.conf";
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
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; form-action 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; upgrade-insecure-requests" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
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
      pkgs.openssl
    ];
    text = ''
      set -euo pipefail

      raw_conf=${lib.escapeShellArg nginxHttpConfPath}
      rendered_conf=${lib.escapeShellArg nginxRenderedHttpConfPath}
      username_file=${lib.escapeShellArg nginxPreviewUsernamePath}
      password_file=${lib.escapeShellArg nginxPreviewPasswordPath}
      nginx_dir=${lib.escapeShellArg nginxRuntimeDir}
      htpasswd=${lib.escapeShellArg nginxHtpasswdPath}

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

      tmp_conf="$(mktemp "$nginx_dir/http.conf.XXXXXX")"
      cat > "$tmp_conf" <<'NGINX_SECURITY_HEADERS'
      ${nginxSecurityHeaders}
      NGINX_SECURITY_HEADERS
      cat "$raw_conf" >> "$tmp_conf"
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
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
      runtime_dir=${lib.escapeShellArg webpageEnvDir}
      rendered_env=${lib.escapeShellArg webpageRenderedEnvPath}

      install -d -m 0750 -o nginx -g nginx "$runtime_dir"

      set -a
      # shellcheck source=/dev/null
      . "$base_env"
      set +a

      declare -A account_path_by_id
      declare -A account_domain_by_id
      declare -A account_smtp_host_by_id
      declare -A account_smtp_port_by_id

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
        local account_path="''${account_path_by_id[$account_id]:-}"

        [ -n "$account_path" ] || return 1
        [ -r "$account_path" ] || return 1

        load_account_env "$account_path"

        account_domain="''${account_domain_by_id[$account_id]:-}"
        account_address="''${MAIL_ACCOUNT_ADDRESS:-}"
        if [ -z "$account_address" ] && [ -n "''${MAIL_ACCOUNT_LOCALPART:-}" ] && [ -n "$account_domain" ]; then
          account_address="''${MAIL_ACCOUNT_LOCALPART}@$account_domain"
        fi

        account_username="''${MAIL_ACCOUNT_USERNAME:-$account_address}"
        account_password="''${MAIL_ACCOUNT_PASSWORD:-}"
        account_smtp_host="''${MAIL_ACCOUNT_SMTP_HOST:-}"
        [ -n "$account_smtp_host" ] || account_smtp_host="''${MAIL_ACCOUNT_MAIL_HOST:-}"
        [ -n "$account_smtp_host" ] || account_smtp_host="''${account_smtp_host_by_id[$account_id]:-}"
        account_smtp_port="''${MAIL_ACCOUNT_SMTP_PORT:-}"
        [ -n "$account_smtp_port" ] || account_smtp_port="''${account_smtp_port_by_id[$account_id]:-}"

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
        mailbox_set_path="''${entry#*=}"
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
        done
      done < "$mailbox_set_env_path_list"

      public_account="''${WEB_PUBLIC_CONTACT_ACCOUNT:-''${WEB_CONTACT_ACCOUNT:-}}"
      form_account="''${WEB_FORM_ACCOUNT:-''${WEB_CONTACT_ACCOUNT:-}}"

      if [ -n "$public_account" ] && load_account_context "$public_account"; then
        [ -n "''${WEB_CONTACT_EMAIL:-}" ] || WEB_CONTACT_EMAIL="$account_address"
        [ -n "''${WEB_SITE_DOMAIN:-}" ] || WEB_SITE_DOMAIN="$account_domain"
      fi

      if [ -n "$form_account" ] && load_account_context "$form_account"; then
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
      [ -n "''${CONTACT_SITE_URL:-}" ] || CONTACT_SITE_URL="''${WEB_SITE_URL:-}"
      [ -n "''${WEB_REDIRECT_TARGET_URL:-}" ] || WEB_REDIRECT_TARGET_URL="''${WEB_SITE_URL:-/}"

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
        printf '\n# Derived from web/contact/env and generic mailbox secrets.\n'
        for name in \
          WEB_SITE_NAME \
          WEB_SITE_DOMAIN \
          WEB_SITE_URL \
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
    '';
  };

  syncWebpageSource = pkgs.writeShellApplication {
    name = "${hostName}-sync-webpage-source";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gitMinimal
      pkgs.rsync
    ];
    text = ''
      set -euo pipefail

      repo_url=${lib.escapeShellArg webpageRepoUrl}
      repo_branch=${lib.escapeShellArg webpageRepoBranch}
      token_file=${lib.escapeShellArg githubTokenPath}
      src=${lib.escapeShellArg webpageSourceDir}
      dst=${lib.escapeShellArg webpageRuntimeDir}
      restart_marker=${lib.escapeShellArg webpageRestartMarker}

      keep_existing_app() {
        if [ -f "$dst/run-server.py" ]; then
          echo "webpage sync failed; keeping existing runtime app in $dst" >&2
          exit 0
        fi

        echo "webpage sync failed and no existing runtime app is available in $dst" >&2
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
        git -C "$src" remote set-url origin "$repo_url" || keep_existing_app
        git -C "$src" fetch --depth=1 origin "$repo_branch" || keep_existing_app
        git -C "$src" checkout -B "$repo_branch" FETCH_HEAD || keep_existing_app
        git -C "$src" reset --hard FETCH_HEAD || keep_existing_app
        git -C "$src" clean -fdx || keep_existing_app
      else
        tmp="$(mktemp -d "$(dirname "$src")/source.tmp.XXXXXX")"
        trap 'rm -f "$askpass"; rm -rf "$tmp"' EXIT
        git clone --depth=1 --branch "$repo_branch" "$repo_url" "$tmp/repo" || keep_existing_app
        rm -rf "$src"
        mv "$tmp/repo" "$src"
        rmdir "$tmp"
      fi

      runtime_rev="$(cat "$dst/.source-rev" 2>/dev/null || true)"
      source_rev="$(git -C "$src" rev-parse HEAD)"

      chown -R root:root "$src"
      rsync -a --delete \
        --chown=nginx:nginx \
        --chmod=D755,F644 \
        --exclude='.git/' \
        --filter='protect .env' \
        --filter='protect .env.*' \
        "$src/" "$dst/"

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
  sops.secrets =
    {
      "web/nginx/http_conf" = {
        sopsFile = runtimeSopsFile;
        owner = "nginx";
        group = "nginx";
        mode = "0440";
        restartUnits = [
          nginxRuntimeConfigUnit
          "nginx.service"
        ];
      };

      "web/contact/env" = {
        sopsFile = runtimeSopsFile;
        owner = "nginx";
        group = "nginx";
        mode = "0440";
        restartUnits = [
          webpageEnvUnit
          webpageUnit
        ];
      };

      "web/preview/username" = {
        sopsFile = runtimeSopsFile;
        owner = "nginx";
        group = "nginx";
        mode = "0440";
        restartUnits = [
          nginxRuntimeConfigUnit
          "nginx.service"
        ];
      };

      "web/preview/password" = {
        sopsFile = runtimeSopsFile;
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
    after = [ certMailUnit ];
    before = [ "nginx.service" ];
    requires = [ certMailUnit ];
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
    ];
    script = "${lib.getExe prepareNginxRuntime}";
  };

  systemd.services.${webpageSyncService} = {
    description = "Sync s-gamma webpage source from GitHub";
    after = [ "network-online.target" ];
    before = [ webpageUnit ];
    wants = [ "network-online.target" ];
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
    requires = [ webpageEnvUnit ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOST = webpageHost;
      PORT = toString webpagePort;
      WEB_ROOT = "webpagina";
      CORS_ALLOW_ORIGIN = "*";
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
      auth_basic "preview";
      auth_basic_user_file ${nginxHtpasswdPath};

      include ${nginxRenderedHttpConfPath};
    '';
  };

  systemd.services.nginx = {
    after = [
      networkAddressesUnit
      certMailUnit
      nginxRuntimeConfigUnit
      webpageUnit
    ];
    requires = [
      networkAddressesUnit
      certMailUnit
      nginxRuntimeConfigUnit
      webpageUnit
    ];
    preStart = lib.mkBefore (waitForReadableFiles "nginx" [
      nginxRenderedHttpConfPath
      nginxHtpasswdPath
    ]);
    serviceConfig.TimeoutStartSec = "5min";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
