{ config
, lib
, mailboxSets ? null
, name
, pkgs
, ...
}:
let
  hostName = name;
  networkAddressesUnit = "${hostName}-network-addresses.service";
  certMailService = "${hostName}-cert-mail";
  certMailUnit = "${certMailService}.service";
  mailRuntimeConfigUnit = "${hostName}-mail-runtime-config.service";
  nginxRuntimeConfigUnit = "${hostName}-nginx-runtime-config.service";
  runtimeRoot = "/run/${hostName}";
  mailTlsRuntimeDir = "${runtimeRoot}/mail/tls";
  mailAcmeDir = "/var/lib/acme/${hostName}-mail";
  mailAcmeLegoDir = "${mailAcmeDir}/lego";

  mailEnvPath = config.sops.secrets."mail/server/env".path;
  networkAddressEnvPath = config.sops.secrets."network/address_env".path;
  mailTlsFullchainPath = config.sGamma.certs.mail.fullchainPath;
  mailTlsKeyPath = config.sGamma.certs.mail.keyPath;
  emptyMailboxPathList = pkgs.writeText "${hostName}-cert-empty-mailbox-env-paths" "";
  mailboxSetEnvPathsConfig =
    if mailboxSets == null then {
      pathList = emptyMailboxPathList;
      paths = [ ];
    } else
      mailboxSets.mkEnvPaths {
        inherit config lib pkgs;
        name = "${hostName}-cert-mailbox-set-env-paths";
        secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
      };
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailboxSetEnvPaths = mailboxSetEnvPathsConfig.paths;

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
      pkgs.dnsutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.lego
      pkgs.openssl
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      network_env_file=${lib.escapeShellArg networkAddressEnvPath}
      runtime_dir=${lib.escapeShellArg mailTlsRuntimeDir}
      runtime_fullchain=${lib.escapeShellArg mailTlsFullchainPath}
      runtime_key=${lib.escapeShellArg mailTlsKeyPath}
      acme_dir=${lib.escapeShellArg mailAcmeDir}
      lego_dir=${lib.escapeShellArg mailAcmeLegoDir}
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}

      if [ ! -r "$env_file" ]; then
        echo "mail certificate env is missing: $env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a

      set -a
      # shellcheck disable=SC1090
      . "$network_env_file"
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
      require_env PUBLIC_IPV4
      require_env WEB_IPV6

      acme_email="''${MAIL_ACME_EMAIL:-postmaster@$MAIL_FQDN}"

      primary_domain=""
      domain_names=()
      domain_args=()

      add_domain() {
        local domain="$1"
        local existing

        [ -n "$domain" ] || return 0
        case "$domain" in
          *[!A-Za-z0-9.-]* | .* | *..* | *.)
            echo "invalid mail TLS domain: $domain" >&2
            exit 1
            ;;
        esac

        for existing in "''${domain_names[@]}"; do
          if [ "$existing" = "$domain" ]; then
            return 0
          fi
        done

        if [ -z "$primary_domain" ]; then
          primary_domain="$domain"
        fi
        domain_names+=("$domain")
        domain_args+=(--domains "$domain")
      }

      domain_resolves_to_host() {
        local domain="$1"
        local resolver
        local dig_args

        for resolver in "" "@1.1.1.1" "@8.8.8.8" "@9.9.9.9"; do
          dig_args=()
          if [ -n "$resolver" ]; then
            dig_args+=("$resolver")
          fi

          if dig +short "''${dig_args[@]}" "$domain" A | grep -Fx "$PUBLIC_IPV4" >/dev/null; then
            return 0
          fi

          if dig +short "''${dig_args[@]}" "$domain" AAAA | grep -Fx "$WEB_IPV6" >/dev/null; then
            return 0
          fi
        done

        echo "mail certificate: skipping $domain until public DNS resolves to this host" >&2
        return 1
      }

      add_optional_domain() {
        local domain="$1"

        if domain_resolves_to_host "$domain"; then
          add_domain "$domain"
        fi
      }

      add_domain "$MAIL_FQDN"

      for domain in $(words "''${MAIL_TLS_DOMAINS:-}"); do
        add_domain "$domain"
      done

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        mailbox_set_path="''${entry#*=}"
        [ -r "$mailbox_set_path" ] || continue

        unset MAILBOX_DOMAIN MAILBOX_MAIL_HOST
        set -a
        # shellcheck disable=SC1090
        . "$mailbox_set_path"
        set +a

        mailbox_domain="''${MAILBOX_DOMAIN:-}"
        [ -n "$mailbox_domain" ] || continue

        mailbox_mail_host="''${MAILBOX_MAIL_HOST:-mail.$mailbox_domain}"
        add_optional_domain "$mailbox_mail_host"
        add_optional_domain "imap.$mailbox_domain"
        add_optional_domain "$mailbox_domain"
        add_optional_domain "www.$mailbox_domain"
      done < "$mailbox_set_env_path_list"

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

      certificate_matches_request() {
        local certificate="$1"
        local domain

        [ -s "$certificate" ] || return 1
        openssl x509 -checkend 2592000 -noout -in "$certificate" >/dev/null 2>&1 || return 1

        for domain in "''${domain_names[@]}"; do
          if ! openssl x509 -in "$certificate" -noout -ext subjectAltName \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//' \
            | grep -Fx "DNS:$domain" >/dev/null; then
            return 1
          fi
        done

        return 0
      }

      needs_renew=0
      was_nginx_active=0
      if ! certificate_matches_request "$persistent_fullchain" || [ ! -s "$persistent_key" ]; then
        needs_renew=1
      fi

      if [ "$needs_renew" -eq 1 ] && certificate_matches_request "$cert_crt" && [ -s "$cert_key" ]; then
        needs_renew=0
      fi

      if [ "$needs_renew" -eq 1 ]; then
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
            renew \
            --days 99999 \
            --ari-disable \
            --no-random-sleep \
            --force-cert-domains || lego \
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

      chown root:nginx "$runtime_dir" "$runtime_fullchain" "$runtime_key"
      chmod 0750 "$runtime_dir"
      chmod 0640 "$runtime_fullchain" "$runtime_key"

      if [ "$was_nginx_active" -eq 1 ]; then
        systemctl start nginx.service
        was_nginx_active=0
        trap - EXIT
      elif systemctl is-active --quiet nginx.service; then
        systemctl --no-block try-reload-or-restart nginx.service || true
      fi

      for mail_unit in postfix.service dovecot.service; do
        if systemctl is-active --quiet "$mail_unit"; then
          systemctl --no-block try-reload-or-restart "$mail_unit" || true
        fi
      done
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
    sops.secrets =
      {
        "mail/server/env".restartUnits = [
          certMailUnit
        ];
      }
      // builtins.listToAttrs (
        map
          (secret: {
            inherit (secret) name;
            value = {
              inherit (secret) key sopsFile;
              restartUnits = [
                certMailUnit
              ];
            };
          })
          (
            if mailboxSets == null then
              [ ]
            else
              mailboxSets.mailboxSetEnvSecretRefs
          )
      );

    systemd.tmpfiles.rules = [
      "d ${runtimeRoot} 0755 root root -"
      "d ${runtimeRoot}/mail 0755 root root -"
      "d ${mailTlsRuntimeDir} 0750 root nginx -"
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
        nginxRuntimeConfigUnit
        "postfix.service"
        "dovecot.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "10min";
      };
      preStart = waitForReadableFiles "mail certificate" [
        mailEnvPath
        networkAddressEnvPath
      ] + waitForReadableFiles "mail certificate mailbox sets" mailboxSetEnvPaths;
      script = "${lib.getExe renewMailCertificate}";
    };

    systemd.services."${hostName}-mail-runtime-config" = {
      after = [ certMailUnit ];
      requires = [ certMailUnit ];
    };

    systemd.services."${hostName}-nginx-runtime-config" = {
      after = [ certMailUnit ];
      requires = [ certMailUnit ];
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
