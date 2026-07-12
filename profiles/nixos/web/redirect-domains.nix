{ config, lib, pkgs, ... }:
let
  cfg = config.local.web.redirectDomains;
  serviceName = "${config.networking.hostName}-web-redirect-domains";
  serviceUnit = "${serviceName}.service";
  renderedConfPath = "${cfg.runtimeDir}/nginx.conf";
  redirectEnvPath = config.sops.secrets.${cfg.secretName}.path;
  tlsFullchainPath =
    if cfg.tls.fullchainPath == null
    then ""
    else cfg.tls.fullchainPath;
  tlsKeyPath =
    if cfg.tls.keyPath == null
    then ""
    else cfg.tls.keyPath;
  tlsPaths =
    lib.optionals (cfg.tls.enable && cfg.tls.fullchainPath != null && cfg.tls.keyPath != null) [
      cfg.tls.fullchainPath
      cfg.tls.keyPath
    ];

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  renderRedirectDomains = pkgs.writeShellApplication {
    name = "${serviceName}-render";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg redirectEnvPath}
      runtime_dir=${lib.escapeShellArg cfg.runtimeDir}
      rendered_conf=${lib.escapeShellArg renderedConfPath}
      tls_enable=${lib.escapeShellArg (if cfg.tls.enable then "1" else "0")}
      tls_fullchain=${lib.escapeShellArg tlsFullchainPath}
      tls_key=${lib.escapeShellArg tlsKeyPath}

      install -d -m 0750 -o root -g nginx "$runtime_dir"

      set -a
      # shellcheck source=/dev/null
      . "$env_file"
      set +a

      words() {
        local raw="''${1//,/ }"
        raw="''${raw//;/ }"
        local word
        for word in $raw; do
          printf '%s\n' "$word"
        done
      }

      validate_domain() {
        local domain="$1"

        case "$domain" in
          *[!A-Za-z0-9.-]* | .* | *..* | *.)
            echo "invalid web redirect domain: $domain" >&2
            exit 1
            ;;
        esac
      }

      domains=()
      for domain in $(words "''${WEB_REDIRECT_DOMAINS:-}"); do
        [ -n "$domain" ] || continue
        validate_domain "$domain"
        domains+=("$domain")
      done

      target="''${WEB_REDIRECT_TARGET_URL:-}"
      status="''${WEB_REDIRECT_STATUS:-301}"

      case "$status" in
        301|302|307|308)
          ;;
        *)
          echo "WEB_REDIRECT_STATUS must be one of 301, 302, 307, or 308" >&2
          exit 1
          ;;
      esac

      tmp="$(mktemp "$runtime_dir/nginx.conf.XXXXXX")"
      {
        printf '# Generated from SOPS web redirect profile.\n'

        if [ "''${#domains[@]}" -gt 0 ]; then
          if [ -z "$target" ]; then
            echo "WEB_REDIRECT_DOMAINS is set, but WEB_REDIRECT_TARGET_URL is empty" >&2
            exit 1
          fi

          case "$target" in
            http://* | https://*)
              ;;
            *)
              echo "WEB_REDIRECT_TARGET_URL must be an absolute http(s) URL" >&2
              exit 1
              ;;
          esac

          if printf '%s' "$target" | grep -Eq '[[:space:];]'; then
            echo "WEB_REDIRECT_TARGET_URL must not contain whitespace or semicolons" >&2
            exit 1
          fi

          target="''${target%/}"
          server_names="''${domains[*]}"

          cat <<NGINX

      server {
        listen 80;
        listen [::]:80;
        server_name $server_names;
        auth_basic off;
        return $status $target\$request_uri;
      }
      NGINX

          if [ "$tls_enable" = "1" ]; then
            cat <<NGINX

      server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name $server_names;
        auth_basic off;
        ssl_certificate $tls_fullchain;
        ssl_certificate_key $tls_key;
        return $status $target\$request_uri;
      }
      NGINX
          fi
        fi
      } > "$tmp"

      chown root:nginx "$tmp"
      chmod 0440 "$tmp"
      mv "$tmp" "$rendered_conf"

      if systemctl is-active --quiet ${lib.escapeShellArg cfg.nginxUnit}; then
        systemctl try-reload-or-restart ${lib.escapeShellArg cfg.nginxUnit} || true
      fi
    '';
  };
in
{
  options.local.web.redirectDomains = {
    enable = lib.mkEnableOption "SOPS-backed nginx redirect domains";

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "SOPS file containing the web redirect env secret.";
    };

    secretName = lib.mkOption {
      type = lib.types.str;
      default = "web/redirects/env";
      description = "SOPS secret key containing WEB_REDIRECT_* env variables.";
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/${config.networking.hostName}/web-redirect-domains";
      description = "Runtime directory for the generated nginx redirect include.";
    };

    nginxUnit = lib.mkOption {
      type = lib.types.str;
      default = "nginx.service";
      description = "Nginx systemd unit that includes the generated redirect config.";
    };

    afterUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Units that must finish before redirect config rendering.";
    };

    requiresUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Units required before redirect config rendering.";
    };

    tls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to emit HTTPS redirect server blocks.";
      };

      fullchainPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Certificate fullchain path for HTTPS redirect domains.";
      };

      keyPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Certificate key path for HTTPS redirect domains.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sopsFile != null;
        message = "local.web.redirectDomains.sopsFile must be set.";
      }
      {
        assertion = !cfg.tls.enable || (cfg.tls.fullchainPath != null && cfg.tls.keyPath != null);
        message = "local.web.redirectDomains.tls fullchainPath and keyPath must be set when HTTPS redirects are enabled.";
      }
    ];

    sops.secrets.${cfg.secretName} = {
      sopsFile = cfg.sopsFile;
      owner = "root";
      group = "nginx";
      mode = "0440";
      restartUnits = [
        serviceUnit
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.runtimeDir} 0750 root nginx -"
    ];

    systemd.services.${serviceName} = {
      description = "Render nginx redirect domains from SOPS";
      after = cfg.afterUnits;
      requires = cfg.requiresUnits;
      before = [ cfg.nginxUnit ];
      requiredBy = [ cfg.nginxUnit ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      preStart = waitForReadableFiles "web redirect domains" (
        [
          redirectEnvPath
        ]
        ++ tlsPaths
      );
      script = "${lib.getExe renderRedirectDomains}";
    };

    services.nginx.appendHttpConfig = ''
      include ${renderedConfPath};
    '';
  };
}
