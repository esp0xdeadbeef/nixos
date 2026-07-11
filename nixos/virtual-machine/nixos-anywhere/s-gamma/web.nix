{ config, lib, name, pkgs, ... }:
let
  hostName = name;
  networkAddressesService = "${hostName}-network-addresses";
  networkAddressesUnit = "${networkAddressesService}.service";
  nginxRuntimeConfigService = "${hostName}-nginx-runtime-config";
  nginxRuntimeConfigUnit = "${nginxRuntimeConfigService}.service";
  certMailUnit = "${hostName}-cert-mail.service";
  webpageSyncService = "${hostName}-webpage-sync";
  webpageSyncUnit = "${webpageSyncService}.service";
  webpageService = "${hostName}-webpage";
  webpageUnit = "${webpageService}.service";
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;

  runtimeRoot = "/run/${hostName}";
  githubTokenPath = config.sops.secrets.gh-token.path;
  webpageRepoUrl = "https://github.com/esp0xdeadbeef/www.git";
  webpageRepoBranch = "main";
  webpageSourceDir = "/persist/srv/www/source";
  webpageRuntimeDir = "/persist/srv/www/app";
  webpageHost = "127.0.0.1";
  webpagePort = 8080;

  nginxHttpConfPath = config.sops.secrets."web/nginx/http_conf".path;
  webContactEnvPath = config.sops.secrets."web/contact/env".path;
  nginxPreviewUsernamePath = config.sops.secrets."web/preview/username".path;
  nginxPreviewPasswordPath = config.sops.secrets."web/preview/password".path;
  nginxRuntimeDir = "${runtimeRoot}/nginx";
  nginxHtpasswdPath = "${nginxRuntimeDir}/htpasswd";
  nginxRenderedHttpConfPath = "${nginxRuntimeDir}/http.conf";
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
        git -C "$src" remote set-url origin "$repo_url"
        git -C "$src" fetch --depth=1 origin "$repo_branch"
        git -C "$src" checkout -B "$repo_branch" FETCH_HEAD
        git -C "$src" reset --hard FETCH_HEAD
        git -C "$src" clean -fdx
      else
        tmp="$(mktemp -d "$(dirname "$src")/source.tmp.XXXXXX")"
        trap 'rm -f "$askpass"; rm -rf "$tmp"' EXIT
        git clone --depth=1 --branch "$repo_branch" "$repo_url" "$tmp/repo"
        rm -rf "$src"
        mv "$tmp/repo" "$src"
        rmdir "$tmp"
      fi

      chown -R root:root "$src"
      rsync -a --delete \
        --chown=nginx:nginx \
        --chmod=D755,F644 \
        --exclude='.git/' \
        --filter='protect .env' \
        --filter='protect .env.*' \
        "$src/" "$dst/"

      chmod 0755 "$dst/run-server.py" "$dst/start-page.sh"
    '';
  };
in
{
  sops.secrets = {
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
      restartUnits = [ webpageUnit ];
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
  };

  systemd.tmpfiles.rules = [
    "d ${runtimeRoot} 0755 root root -"
    "d ${nginxRuntimeDir} 0750 nginx nginx -"
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
    before = [ webpageUnit ];
    requiredBy = [ webpageUnit ];
    serviceConfig = {
      Type = "oneshot";
    };
    preStart = waitForReadableFiles "webpage sync" [
      githubTokenPath
    ];
    script = "${lib.getExe syncWebpageSource}";
  };

  systemd.services.${webpageService} = {
    description = "Run ${hostName} webpage backend";
    after = [
      "network.target"
      webpageSyncUnit
    ];
    requires = [ webpageSyncUnit ];
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
      EnvironmentFile = webContactEnvPath;
      ExecStart = "${pkgs.python3}/bin/python3 ./run-server.py";
      Restart = "always";
      RestartSec = "5s";
    };
    preStart = waitForReadableFiles "web contact" [
      webContactEnvPath
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
