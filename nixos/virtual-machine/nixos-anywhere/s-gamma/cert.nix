{ config, lib, name, pkgs, ... }:
let
  hostName = name;
  networkAddressesUnit = "${hostName}-network-addresses.service";
  certMailService = "${hostName}-cert-mail";
  certMailUnit = "${certMailService}.service";
  mailRuntimeConfigUnit = "${hostName}-mail-runtime-config.service";
  runtimeRoot = "/run/${hostName}";
  mailTlsRuntimeDir = "${runtimeRoot}/mail/tls";
  mailAcmeDir = "/var/lib/acme/${hostName}-mail";
  mailAcmeLegoDir = "${mailAcmeDir}/lego";

  mailEnvPath = config.sops.secrets."mail/server/env".path;
  mailTlsFullchainPath = config.sGamma.certs.mail.fullchainPath;
  mailTlsKeyPath = config.sGamma.certs.mail.keyPath;

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  renewMailCertificate = pkgs.writeShellApplication {
    name = "${hostName}-renew-mail-certificate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.lego
      pkgs.openssl
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      runtime_dir=${lib.escapeShellArg mailTlsRuntimeDir}
      runtime_fullchain=${lib.escapeShellArg mailTlsFullchainPath}
      runtime_key=${lib.escapeShellArg mailTlsKeyPath}
      acme_dir=${lib.escapeShellArg mailAcmeDir}
      lego_dir=${lib.escapeShellArg mailAcmeLegoDir}

      if [ ! -r "$env_file" ]; then
        echo "mail certificate env is missing: $env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a

      require_env() {
        name="$1"
        if [ -z "$(printenv "$name" || true)" ]; then
          echo "required mail certificate variable is missing: $name" >&2
          exit 1
        fi
      }

      words() {
        printf '%s\n' "$1" | tr ',\t\r\n' ' '
      }

      require_env MAIL_FQDN

      acme_email="''${MAIL_ACME_EMAIL:-postmaster@$MAIL_FQDN}"
      domains_raw="''${MAIL_TLS_DOMAINS:-$MAIL_FQDN}"

      primary_domain=""
      domain_args=()
      for domain in $(words "$domains_raw"); do
        [ -n "$domain" ] || continue
        case "$domain" in
          *[!A-Za-z0-9.-]* | .* | *..* | *.)
            echo "invalid mail TLS domain: $domain" >&2
            exit 1
            ;;
        esac
        if [ -z "$primary_domain" ]; then
          primary_domain="$domain"
        fi
        domain_args+=(--domains "$domain")
      done

      if [ -z "$primary_domain" ]; then
        echo "MAIL_TLS_DOMAINS resolved to an empty domain list" >&2
        exit 1
      fi

      install -d -m 0700 -o root -g root "$acme_dir" "$lego_dir"
      install -d -m 0750 -o root -g root "$runtime_dir"

      cert_crt="$lego_dir/certificates/$primary_domain.crt"
      cert_issuer="$lego_dir/certificates/$primary_domain.issuer.crt"
      cert_key="$lego_dir/certificates/$primary_domain.key"
      persistent_fullchain="$acme_dir/fullchain.pem"
      persistent_key="$acme_dir/key.pem"

      needs_renew=0
      if [ ! -s "$persistent_fullchain" ] || [ ! -s "$persistent_key" ]; then
        needs_renew=1
      elif ! openssl x509 -checkend 2592000 -noout -in "$persistent_fullchain" >/dev/null 2>&1; then
        needs_renew=1
      fi

      if [ "$needs_renew" -eq 1 ]; then
        was_nginx_active=0
        if systemctl is-active --quiet nginx.service; then
          was_nginx_active=1
          systemctl stop nginx.service
        fi

        cleanup() {
          if [ "$was_nginx_active" -eq 1 ]; then
            systemctl start nginx.service || true
          fi
        }
        trap cleanup EXIT

        if [ -s "$cert_crt" ] && [ -s "$cert_key" ]; then
          lego \
            --path "$lego_dir" \
            --accept-tos \
            --email "$acme_email" \
            --http \
            --http.port ":80" \
            "''${domain_args[@]}" \
            renew --days 30 || lego \
            --path "$lego_dir" \
            --accept-tos \
            --email "$acme_email" \
            --http \
            --http.port ":80" \
            "''${domain_args[@]}" \
            run
        else
          lego \
            --path "$lego_dir" \
            --accept-tos \
            --email "$acme_email" \
            --http \
            --http.port ":80" \
            "''${domain_args[@]}" \
            run
        fi

        if [ "$was_nginx_active" -eq 1 ]; then
          systemctl start nginx.service
          was_nginx_active=0
        fi
        trap - EXIT
      fi

      if [ ! -s "$cert_crt" ] || [ ! -s "$cert_key" ]; then
        echo "lego did not produce the expected mail certificate files" >&2
        exit 1
      fi

      tmp_fullchain="$(mktemp "$acme_dir/fullchain.XXXXXX")"
      if [ -s "$cert_issuer" ]; then
        cat "$cert_crt" "$cert_issuer" > "$tmp_fullchain"
      else
        cat "$cert_crt" > "$tmp_fullchain"
      fi

      tmp_key="$(mktemp "$acme_dir/key.XXXXXX")"
      cat "$cert_key" > "$tmp_key"

      chown root:root "$tmp_fullchain" "$tmp_key"
      chmod 0444 "$tmp_fullchain"
      chmod 0400 "$tmp_key"
      mv "$tmp_fullchain" "$persistent_fullchain"
      mv "$tmp_key" "$persistent_key"

      install -m 0444 -o root -g root "$persistent_fullchain" "$runtime_fullchain"
      install -m 0400 -o root -g root "$persistent_key" "$runtime_key"

      if id -g nginx >/dev/null 2>&1; then
        chown root:nginx "$runtime_dir" "$runtime_fullchain" "$runtime_key"
        chmod 0750 "$runtime_dir"
        chmod 0640 "$runtime_fullchain" "$runtime_key"
      fi

      if systemctl is-active --quiet nginx.service; then
        systemctl --no-block try-reload-or-restart nginx.service || true
      fi
    '';
  };
in
{
  options.sGamma.certs.mail = {
    fullchainPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${mailTlsRuntimeDir}/fullchain.pem";
      description = "Runtime fullchain path for the mail TLS certificate.";
    };

    keyPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${mailTlsRuntimeDir}/key.pem";
      description = "Runtime private key path for the mail TLS certificate.";
    };
  };

  config = {
    sops.secrets."mail/server/env".restartUnits = [
      certMailUnit
    ];

    systemd.tmpfiles.rules = [
      "d ${runtimeRoot} 0755 root root -"
      "d ${runtimeRoot}/mail 0755 root root -"
      "d ${mailTlsRuntimeDir} 0750 root root -"
      "d ${mailAcmeDir} 0700 root root -"
    ];

    systemd.services.${certMailService} = {
      description = "Renew ${hostName} mail certificate from SOPS";
      after = [
        "network-online.target"
        networkAddressesUnit
      ];
      wants = [ "network-online.target" ];
      requires = [ networkAddressesUnit ];
      before = [
        mailRuntimeConfigUnit
        "postfix.service"
        "dovecot.service"
      ];
      requiredBy = [ mailRuntimeConfigUnit ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
      };
      preStart = waitForReadableFiles "mail certificate" [
        mailEnvPath
      ];
      script = "${lib.getExe renewMailCertificate}";
    };

    systemd.timers.${certMailService} = {
      description = "Renew ${hostName} mail certificate";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "2h";
        Persistent = true;
      };
    };
  };
}
