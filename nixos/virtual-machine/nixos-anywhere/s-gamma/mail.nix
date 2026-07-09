{ config
, inputs
, lib
, pkgs
, ...
}:
let
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;
  mailClientSopsFile = ../../../../secrets/mail-client.yaml;

  runtimeRoot = "/run/s-gamma";
  postfixRuntimeDir = "${runtimeRoot}/mail/postfix";
  dovecotRuntimeDir = "${runtimeRoot}/mail/dovecot";
  webpageSource = inputs.webpage;
  webpageRuntimeDir = "/persist/srv/kvk/app";
  webpageHost = "127.0.0.1";
  webpagePort = 8080;

  mailEnvPath = config.sops.secrets."mail/server/env".path;
  mailPasswordPath = config.sops.secrets."mail_client/shared/password".path;
  tlsFullchainPath = config.sops.secrets."mail/tls/fullchain_pem".path;
  tlsKeyPath = config.sops.secrets."mail/tls/key_pem".path;
  networkAddressEnvPath = config.sops.secrets."network/address_env".path;
  dnsNamedConfPath = config.sops.secrets."dns/named_conf".path;
  dnsZonePath = config.sops.secrets."dns/zone_001".path;
  nginxHttpConfPath = config.sops.secrets."web/nginx/http_conf".path;
  nginxPreviewUsernamePath = config.sops.secrets."web/preview/username".path;
  nginxPreviewPasswordPath = config.sops.secrets."web/preview/password".path;
  nginxRuntimeDir = "${runtimeRoot}/nginx";
  nginxHtpasswdPath = "${nginxRuntimeDir}/htpasswd";

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  prepareNginxRuntime = pkgs.writeShellApplication {
    name = "s-gamma-prepare-nginx-runtime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.openssl
    ];
    text = ''
      set -euo pipefail

      conf=${lib.escapeShellArg nginxHttpConfPath}
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
      ' "$conf" | while IFS= read -r cert_path; do
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
    name = "s-gamma-sync-webpage-source";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rsync
    ];
    text = ''
      set -euo pipefail

      src=${lib.escapeShellArg "${webpageSource}/"}
      dst=${lib.escapeShellArg webpageRuntimeDir}

      install -d -m 0755 -o nginx -g nginx "$dst"
      rsync -a --delete \
        --chown=nginx:nginx \
        --chmod=D755,F644 \
        --filter='protect .env' \
        --filter='protect .env.*' \
        "$src" "$dst/"

      chmod 0755 "$dst/run-server.py" "$dst/start-page.sh"
    '';
  };

  configureNetworkAddresses = pkgs.writeShellApplication {
    name = "s-gamma-configure-network-addresses";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.iproute2
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg networkAddressEnvPath}
      interface="''${NETWORK_INTERFACE:-ens3}"

      if [ ! -r "$env_file" ]; then
        echo "network address env is missing: $env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a

      require_env() {
        name="$1"
        if [ -z "$(printenv "$name" || true)" ]; then
          echo "required network address variable is missing: $name" >&2
          exit 1
        fi
      }

      require_env WEB_IPV6
      require_env WEB_IPV6_PREFIX_LENGTH

      if ! printf '%s\n' "$WEB_IPV6_PREFIX_LENGTH" | grep -Eq '^[0-9]+$'; then
        echo "WEB_IPV6_PREFIX_LENGTH must be numeric" >&2
        exit 1
      fi

      ip -6 addr replace "$WEB_IPV6/$WEB_IPV6_PREFIX_LENGTH" dev "$interface"
    '';
  };

  renderMailRuntime = pkgs.writeShellApplication {
    name = "s-gamma-render-mail-runtime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dovecot
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.postfix
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      password_file=${lib.escapeShellArg mailPasswordPath}
      postfix_dir=${lib.escapeShellArg postfixRuntimeDir}
      dovecot_dir=${lib.escapeShellArg dovecotRuntimeDir}
      tls_fullchain=${lib.escapeShellArg tlsFullchainPath}
      tls_key=${lib.escapeShellArg tlsKeyPath}

      if [ ! -r "$env_file" ]; then
        echo "mail runtime env is missing: $env_file" >&2
        exit 1
      fi

      if [ ! -r "$password_file" ]; then
        echo "shared mail password is missing: $password_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      set +a

      require_env() {
        name="$1"
        if [ -z "$(printenv "$name" || true)" ]; then
          echo "required mail runtime variable is missing: $name" >&2
          exit 1
        fi
      }

      words() {
        printf '%s\n' "$1" | tr ',\t\r\n' ' '
      }

      ref_to_address() {
        ref="$1"
        address="$(printenv "MAIL_''${ref}_ADDRESS" || true)"
        if [ -n "$address" ]; then
          printf '%s\n' "$address"
        else
          printf '%s\n' "$ref"
        fi
      }

      shared_var() {
        shared_id="$1"
        field="$2"
        printenv "MAIL_SHARED_''${shared_id}_''${field}" || true
      }

      require_env MAIL_FQDN
      require_env MAIL_DOMAIN
      require_env MAIL_DOMAINS
      require_env MAIL_ACCOUNTS

      install -d -m 0750 -o root -g postfix "$postfix_dir"
      install -d -m 0750 -o root -g dovecot2 "$dovecot_dir"

      vdomains="$postfix_dir/vdomains"
      valias="$postfix_dir/valias"
      vaccounts_raw="$postfix_dir/vaccounts.raw"
      vaccounts="$postfix_dir/vaccounts"
      passwd_file="$dovecot_dir/passwd"

      : > "$vdomains"
      : > "$valias"
      : > "$vaccounts_raw"
      : > "$vaccounts"
      : > "$passwd_file"

      for domain in $(words "$MAIL_DOMAINS"); do
        [ -n "$domain" ] || continue
        printf '%s OK\n' "$domain" >> "$vdomains"
      done

      password="$(tr -d '\r\n' < "$password_file")"
      password_hash="$(doveadm pw -s BLF-CRYPT -p "$password")"
      unset password

      for account_id in $(words "$MAIL_ACCOUNTS"); do
        [ -n "$account_id" ] || continue

        address_var="MAIL_''${account_id}_ADDRESS"
        aliases_var="MAIL_''${account_id}_ALIASES"
        address="$(printenv "$address_var" || true)"
        aliases="$(printenv "$aliases_var" || true)"

        if [ -z "$address" ]; then
          echo "missing address variable for mail account id: $account_id" >&2
          exit 1
        fi

        printf '%s %s\n' "$address" "$address" >> "$valias"
        printf '%s %s\n' "$address" "$address" >> "$vaccounts_raw"
        printf '%s:%s::::::\n' "$address" "$password_hash" >> "$passwd_file"

        for alias in $(words "$aliases"); do
          [ -n "$alias" ] || continue
          printf '%s %s\n' "$alias" "$address" >> "$valias"
          printf '%s %s\n' "$alias" "$address" >> "$vaccounts_raw"
        done
      done

      for shared_id in $(words "''${MAIL_SHARED_MAILBOXES:-}"); do
        [ -n "$shared_id" ] || continue

        owner_ref="$(shared_var "$shared_id" OWNER)"
        user_refs="$(shared_var "$shared_id" USERS)"
        [ -n "$owner_ref" ] || continue
        [ -n "$user_refs" ] || continue

        owner="$(ref_to_address "$owner_ref")"
        printf '%s %s\n' "$owner" "$owner" >> "$vaccounts_raw"

        for user_ref in $(words "$user_refs"); do
          [ -n "$user_ref" ] || continue
          printf '%s %s\n' "$owner" "$(ref_to_address "$user_ref")" >> "$vaccounts_raw"
        done
      done

      awk '
        {
          sender = $1
          if (!(sender in seen_sender)) {
            seen_sender[sender] = 1
            sender_order[++sender_count] = sender
          }

          for (i = 2; i <= NF; i++) {
            split($i, logins, ",")
            for (j in logins) {
              login = logins[j]
              if (login == "") {
                continue
              }

              key = sender SUBSEP login
              if (!(key in seen_login)) {
                seen_login[key] = 1
                login_list[sender] = login_list[sender] (login_list[sender] == "" ? "" : ",") login
              }
            }
          }
        }

        END {
          for (i = 1; i <= sender_count; i++) {
            sender = sender_order[i]
            print sender, login_list[sender]
          }
        }
      ' "$vaccounts_raw" > "$vaccounts"

      rm -f "$vaccounts_raw"
      chown root:postfix "$vdomains" "$valias" "$vaccounts"
      chmod 0640 "$vdomains" "$valias" "$vaccounts"
      chown root:dovecot2 "$passwd_file"
      chmod 0440 "$passwd_file"

      postmap "$vdomains"
      postmap "$valias"
      postmap "$vaccounts"
      chown root:postfix "$vdomains.db" "$valias.db" "$vaccounts.db"
      chmod 0640 "$vdomains.db" "$valias.db" "$vaccounts.db"

      main_cf=/var/lib/postfix/conf/main.cf
      if [ -L "$main_cf" ]; then
        cp --remove-destination "$(readlink -f "$main_cf")" "$main_cf"
      fi

      postconf -c /var/lib/postfix/conf -e \
        "myhostname = $MAIL_FQDN" \
        "mydomain = $MAIL_DOMAIN" \
        "myorigin = $MAIL_DOMAIN" \
        "smtpd_banner = $MAIL_FQDN ESMTP" \
        "virtual_mailbox_domains = hash:$vdomains" \
        "virtual_mailbox_maps = hash:$valias" \
        "virtual_alias_maps = hash:$valias" \
        "smtpd_sender_login_maps = hash:$vaccounts" \
        "smtpd_tls_chain_files = $tls_key $tls_fullchain"

      postfix -c /var/lib/postfix/conf check
    '';
  };

  syncSharedMailSubscriptions = pkgs.writeShellApplication {
    name = "s-gamma-sync-shared-mail-subscriptions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dovecot
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      vmail_root=/var/vmail

      words() {
        printf '%s\n' "''${1:-}" | tr ',\t\r\n' ' '
      }

      ref_to_address() {
        ref="$1"
        address="$(printenv "MAIL_''${ref}_ADDRESS" || true)"
        if [ -n "$address" ]; then
          printf '%s\n' "$address"
        else
          printf '%s\n' "$ref"
        fi
      }

      shared_var() {
        shared_id="$1"
        field="$2"
        printenv "MAIL_SHARED_''${shared_id}_''${field}" || true
      }

      if [ -r "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
      fi

      if [ ! -d "$vmail_root" ]; then
        echo "shared-mail-subscriptions: no vmail root present"
        exit 0
      fi

      list_users() {
        doveadm user '*' 2>/dev/null || true
      }

      mailbox_from_acl_path() {
        acl_file="$1"
        mailbox_dir="$(dirname "$acl_file")"

        rel="''${mailbox_dir#"$vmail_root"/}"
        domain="''${rel%%/*}"
        rel="''${rel#*/}"
        owner="''${rel%%/*}"
        rel="''${rel#*/}"

        if [ -z "$domain" ] || [ -z "$owner" ] || [ "$rel" = "$owner" ]; then
          return 1
        fi

        case "$rel" in
          mail)
            printf 'shared.%s\n' "$owner"
            ;;
          mail/.*)
            suffix="''${rel#mail/.}"
            printf 'shared.%s.%s\n' "$owner" "$suffix"
            ;;
          *)
            return 1
            ;;
        esac
      }

      sync_declared_shared_mailboxes() {
        for shared_id in $(words "''${MAIL_SHARED_MAILBOXES:-}"); do
          [ -n "$shared_id" ] || continue

          owner_ref="$(shared_var "$shared_id" OWNER)"
          user_refs="$(shared_var "$shared_id" USERS)"
          mailbox="$(shared_var "$shared_id" MAILBOX)"
          rights="$(shared_var "$shared_id" RIGHTS)"

          if [ -z "$owner_ref" ] || [ -z "$user_refs" ]; then
            echo "shared-mail-subscriptions: skipping incomplete shared mailbox declaration: $shared_id" >&2
            continue
          fi

          [ -n "$mailbox" ] || mailbox=INBOX
          [ -n "$rights" ] || rights="lookup read write write-seen write-deleted insert post expunge create delete"

          owner="$(ref_to_address "$owner_ref")"
          if ! doveadm user "$owner" >/dev/null 2>&1; then
            echo "shared-mail-subscriptions: owner is not a Dovecot user: $owner_ref" >&2
            continue
          fi

          if ! doveadm mailbox status -u "$owner" uidvalidity "$mailbox" >/dev/null 2>&1; then
            doveadm mailbox create -u "$owner" -s "$mailbox" >/dev/null 2>&1 || true
          fi

          rights_args=()
          for right in $(words "$rights"); do
            [ -n "$right" ] || continue
            rights_args+=("$right")
          done

          for user_ref in $(words "$user_refs"); do
            [ -n "$user_ref" ] || continue
            user="$(ref_to_address "$user_ref")"

            if ! doveadm user "$user" >/dev/null 2>&1; then
              echo "shared-mail-subscriptions: ACL user is not a Dovecot user: $user_ref" >&2
              continue
            fi

            doveadm acl add -u "$owner" "$mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
          done
        done
      }

      subscribe_user() {
        user="$1"
        mailbox="$2"

        if ! doveadm user "$user" >/dev/null 2>&1; then
          return 0
        fi

        if ! doveadm mailbox status -u "$user" uidvalidity "$mailbox" >/dev/null 2>&1; then
          echo "shared-mail-subscriptions: mailbox is not visible for ACL user" >&2
          return 1
        fi

        doveadm mailbox subscribe -u "$user" "$mailbox" >/dev/null
      }

      subscribed=0
      failed=0

      sync_declared_shared_mailboxes

      while IFS= read -r acl_file; do
        mailbox="$(mailbox_from_acl_path "$acl_file" || true)"
        [ -n "$mailbox" ] || continue

        while read -r identifier rights _rest; do
          [ -n "''${identifier:-}" ] || continue
          case "$identifier" in
            \#*) continue ;;
          esac

          case "''${rights:-}" in
            *l*) ;;
            *) continue ;;
          esac

          case "$identifier" in
            user=*)
              user="''${identifier#user=}"
              if subscribe_user "$user" "$mailbox"; then
                subscribed=$((subscribed + 1))
              else
                failed=$((failed + 1))
              fi
              ;;
            authenticated|anyone)
              while IFS= read -r user; do
                [ -n "$user" ] || continue
                if subscribe_user "$user" "$mailbox"; then
                  subscribed=$((subscribed + 1))
                else
                  failed=$((failed + 1))
                fi
              done < <(list_users)
              ;;
          esac
        done < "$acl_file"
      done < <(find "$vmail_root" -type f -name dovecot-acl)

      if [ "$failed" -ne 0 ]; then
        echo "shared-mail-subscriptions: failed to sync $failed subscription(s)" >&2
        exit 1
      fi

      echo "shared-mail-subscriptions: synced $subscribed subscription(s)"
    '';
  };

  commonSubmissionOptions = {
    smtpd_tls_security_level = "encrypt";
    smtpd_sasl_auth_enable = "yes";
    smtpd_sasl_type = "dovecot";
    smtpd_sasl_path = "/run/dovecot2/auth";
    smtpd_sasl_security_options = "noanonymous";
    smtpd_client_restrictions = "permit_sasl_authenticated,reject";
    smtpd_sender_login_maps = "hash:${postfixRuntimeDir}/vaccounts";
    smtpd_sender_restrictions = "reject_sender_login_mismatch";
    smtpd_recipient_restrictions = "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
    milter_macro_daemon_name = "ORIGINATING";
  };
in
{
  users.groups.virtualMail = { };
  users.users.virtualMail = {
    isSystemUser = true;
    group = "virtualMail";
    home = "/var/vmail";
  };

  sops.secrets = {
    "network/address_env" = {
      sopsFile = runtimeSopsFile;
      mode = "0400";
      restartUnits = [ "s-gamma-network-addresses.service" ];
    };

    "mail/server/env" = {
      sopsFile = runtimeSopsFile;
      restartUnits = [
        "s-gamma-mail-runtime-config.service"
        "postfix.service"
        "dovecot.service"
      ];
    };

    "mail/tls/fullchain_pem" = {
      sopsFile = runtimeSopsFile;
      mode = "0400";
      restartUnits = [
        "postfix.service"
        "dovecot.service"
      ];
    };

    "mail/tls/key_pem" = {
      sopsFile = runtimeSopsFile;
      mode = "0400";
      restartUnits = [
        "postfix.service"
        "dovecot.service"
      ];
    };

    "dns/named_conf" = {
      sopsFile = runtimeSopsFile;
      owner = "named";
      group = "named";
      mode = "0440";
      restartUnits = [ "bind.service" ];
    };

    "dns/zone_001" = {
      sopsFile = runtimeSopsFile;
      owner = "named";
      group = "named";
      mode = "0440";
      restartUnits = [ "bind.service" ];
    };

    "github/webpage_pat" = {
      sopsFile = runtimeSopsFile;
      mode = "0400";
    };

    "web/nginx/http_conf" = {
      sopsFile = runtimeSopsFile;
      owner = "nginx";
      group = "nginx";
      mode = "0440";
      restartUnits = [ "nginx.service" ];
    };

    "web/preview/username" = {
      sopsFile = runtimeSopsFile;
      owner = "nginx";
      group = "nginx";
      mode = "0440";
      restartUnits = [
        "s-gamma-nginx-runtime-config.service"
        "nginx.service"
      ];
    };

    "web/preview/password" = {
      sopsFile = runtimeSopsFile;
      owner = "nginx";
      group = "nginx";
      mode = "0440";
      restartUnits = [
        "s-gamma-nginx-runtime-config.service"
        "nginx.service"
      ];
    };

    "mail_client/shared/password".sopsFile = mailClientSopsFile;
  };

  systemd.tmpfiles.rules = [
    "d ${runtimeRoot} 0755 root root -"
    "d ${runtimeRoot}/mail 0755 root root -"
    "d ${postfixRuntimeDir} 0750 root postfix -"
    "d ${dovecotRuntimeDir} 0750 root dovecot2 -"
    "d ${nginxRuntimeDir} 0750 nginx nginx -"
    "d /persist/srv 0755 root root -"
    "d /persist/srv/kvk 0755 root root -"
    "d ${webpageRuntimeDir} 0755 nginx nginx -"
    "d /var/lib/postfix/data 0700 postfix postfix -"
    "z /var/lib/postfix/data 0700 postfix postfix -"
    "z /var/lib/postfix/data/master.lock 0600 postfix postfix -"
    "z /var/lib/postfix/data/prng_exch 0600 postfix postfix -"
    "d /var/vmail 0750 virtualMail virtualMail -"
    "d /var/lib/dovecot 0755 root root -"
    "d /var/lib/dovecot/db 0770 virtualMail virtualMail -"
    "z /var/lib/dovecot/db 0770 virtualMail virtualMail -"
    "z /var/lib/acme 0755 root root -"
    "d /var/log/nginx 0750 nginx nginx -"
    "z /var/log/nginx 0750 nginx nginx -"
    "z /var/log/nginx/access.log 0640 nginx nginx -"
    "z /var/log/nginx/error.log 0640 nginx nginx -"
  ];

  systemd.services.s-gamma-network-addresses = {
    description = "Configure s-gamma runtime network addresses from SOPS";
    after = [ "network.target" ];
    before = [
      "bind.service"
      "nginx.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
    };
    preStart = waitForReadableFiles "network addresses" [
      networkAddressEnvPath
    ];
    script = "${lib.getExe configureNetworkAddresses}";
  };

  systemd.services.s-gamma-mail-runtime-config = {
    description = "Render s-gamma mail runtime maps from SOPS";
    after = [ "postfix-setup.service" ];
    requires = [ "postfix-setup.service" ];
    before = [
      "postfix.service"
      "dovecot.service"
    ];
    requiredBy = [
      "postfix.service"
      "dovecot.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "5min";
    };
    preStart = waitForReadableFiles "mail runtime" [
      mailEnvPath
      mailPasswordPath
      tlsFullchainPath
      tlsKeyPath
    ];
    script = "${lib.getExe renderMailRuntime}";
  };

  systemd.services.s-gamma-nginx-runtime-config = {
    description = "Prepare s-gamma nginx runtime files from SOPS";
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
    ];
    script = "${lib.getExe prepareNginxRuntime}";
  };

  systemd.services.s-gamma-webpage-sync = {
    description = "Sync pinned s-gamma webpage source";
    before = [ "s-gamma-webpage.service" ];
    requiredBy = [ "s-gamma-webpage.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${lib.getExe syncWebpageSource}";
  };

  systemd.services.s-gamma-webpage = {
    description = "Run s-gamma webpage backend";
    after = [
      "network.target"
      "s-gamma-webpage-sync.service"
    ];
    requires = [ "s-gamma-webpage-sync.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOST = webpageHost;
      PORT = toString webpagePort;
      WEB_ROOT = "webpagina";
      CORS_ALLOW_ORIGIN = "*";
      MAIL_DRY_RUN = "1";
    };
    path = [ pkgs.python3 ];
    serviceConfig = {
      User = "nginx";
      Group = "nginx";
      WorkingDirectory = webpageRuntimeDir;
      ExecStart = "${pkgs.python3}/bin/python3 ./run-server.py";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  systemd.services.postfix = {
    after = [
      "dovecot.service"
      "s-gamma-mail-runtime-config.service"
    ];
    requires = [
      "dovecot.service"
      "s-gamma-mail-runtime-config.service"
    ];
  };

  systemd.services.dovecot = {
    after = [ "s-gamma-mail-runtime-config.service" ];
    requires = [ "s-gamma-mail-runtime-config.service" ];
  };

  systemd.services.s-gamma-mail-shared-subscriptions = {
    description = "Subscribe users to Dovecot shared mailboxes from ACL state";
    after = [
      "dovecot.service"
      "s-gamma-mail-runtime-config.service"
    ];
    requires = [
      "dovecot.service"
      "s-gamma-mail-runtime-config.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe syncSharedMailSubscriptions;
    };
  };

  systemd.timers.s-gamma-mail-shared-subscriptions = {
    description = "Refresh Dovecot shared mailbox subscriptions";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      AccuracySec = "1min";
      Persistent = true;
    };
  };

  services.postfix = {
    enable = true;
    enableSmtp = true;
    enableSubmission = true;
    enableSubmissions = true;

    settings.main = {
      myhostname = "localhost.invalid";
      mydestination = "";
      recipient_delimiter = "+";
      disable_vrfy_command = true;
      message_size_limit = 20971520;

      virtual_transport = "lmtp:unix:/run/dovecot2/dovecot-lmtp";
      lmtp_destination_recipient_limit = "1";

      smtpd_sasl_type = "dovecot";
      smtpd_sasl_path = "/run/dovecot2/auth";
      smtpd_sasl_auth_enable = true;
      smtpd_relay_restrictions = [
        "permit_mynetworks"
        "permit_sasl_authenticated"
        "reject_unauth_destination"
      ];
      smtpd_tls_auth_only = true;

      smtpd_tls_chain_files = [
        tlsKeyPath
        tlsFullchainPath
      ];
      smtpd_tls_security_level = "may";
      smtpd_tls_protocols = ">=TLSv1.2";
      smtpd_tls_mandatory_protocols = ">=TLSv1.2";
      smtpd_tls_ciphers = "high";
      smtpd_tls_mandatory_ciphers = "high";

      smtp_dns_support_level = "dnssec";
      smtp_tls_security_level = "dane";
      smtp_tls_protocols = ">=TLSv1.2";
      smtp_tls_mandatory_protocols = ">=TLSv1.2";
      smtp_tls_ciphers = "high";
      smtp_tls_mandatory_ciphers = "high";
    };

    submissionOptions = commonSubmissionOptions;
    submissionsOptions = commonSubmissionOptions;
  };

  services.dovecot2 = {
    enable = true;
    package = pkgs.dovecot;
    enablePAM = lib.mkForce false;

    settings = {
      dovecot_config_version = config.services.dovecot2.package.version;
      dovecot_storage_version = config.services.dovecot2.package.version;

      protocols = {
        imap = true;
        lmtp = true;
      };

      auth_mechanisms = [
        "plain"
        "login"
      ];

      mail_uid = "virtualMail";
      mail_gid = "virtualMail";
      mail_driver = "maildir";
      mail_path = "~/mail";
      mail_home = "/var/vmail/%{user | domain}/%{user | username}";
      mail_access_groups = "virtualMail";
      mail_plugins.acl = true;
      mailbox_list_layout = "Maildir++";
      acl_defaults_from_inbox = true;
      acl_driver = "vfile";

      "acl_sharing_map"."dict file".path = "/var/lib/dovecot/db/shared-mailboxes.db";

      "namespace inbox" = {
        inbox = true;
        separator = ".";
        "mailbox \"Archive\"" = {
          auto = "subscribe";
        };
        "mailbox \"Drafts\"" = {
          auto = "subscribe";
          special_use = "\\Drafts";
        };
        "mailbox \"Junk\"" = {
          auto = "subscribe";
          special_use = "\\Junk";
        };
        "mailbox \"Sent\"" = {
          auto = "subscribe";
          special_use = "\\Sent";
        };
        "mailbox \"Trash\"" = {
          auto = "subscribe";
          special_use = "\\Trash";
        };
      };

      "namespace shared" = {
        type = "shared";
        separator = ".";
        prefix = "shared.$username.";
        list = "children";
        subscriptions = false;
        mail_driver = "maildir";
        mail_path = "%{owner_home}/mail";
        mail_index_private_path = "~/mail/shared/%{owner_user}";
      };

      "passdb sops-file" = {
        driver = "passwd-file";
        passwd_file_path = "${dovecotRuntimeDir}/passwd";
      };

      "userdb static" = {
        driver = "static";
        fields = {
          home = "/var/vmail/%{user | domain}/%{user | username}";
          uid = "virtualMail";
          gid = "virtualMail";
        };
      };

      "service auth"."unix_listener auth" = {
        user = "postfix";
        group = "postfix";
        mode = "0660";
      };

      "service lmtp"."unix_listener dovecot-lmtp" = {
        user = "postfix";
        group = "postfix";
        mode = "0600";
      };

      "service imap-login" = {
        "inet_listener imap".port = 143;
        "inet_listener imaps" = {
          port = 993;
          ssl = true;
        };
      };

      "protocol imap".mail_plugins.imap_acl = true;

      ssl = "required";
      ssl_server_cert_file = tlsFullchainPath;
      ssl_server_key_file = tlsKeyPath;
      ssl_min_protocol = "TLSv1.2";
    };
  };

  services.bind = {
    enable = true;
    checkConfig = false;
    extraConfig = ''
      include "${dnsNamedConfPath}";
    '';
  };

  systemd.services.bind = {
    preStart = lib.mkBefore (waitForReadableFiles "bind" [
      dnsNamedConfPath
      dnsZonePath
    ]);
    serviceConfig.TimeoutStartSec = "5min";
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

      include ${nginxHttpConfPath};
    '';
  };

  systemd.services.nginx = {
    after = [
      "s-gamma-nginx-runtime-config.service"
      "s-gamma-webpage.service"
    ];
    requires = [
      "s-gamma-nginx-runtime-config.service"
      "s-gamma-webpage.service"
    ];
    preStart = lib.mkBefore (waitForReadableFiles "nginx" [
      nginxHttpConfPath
      nginxHtpasswdPath
    ]);
    serviceConfig.TimeoutStartSec = "5min";
  };

  networking.firewall.allowedTCPPorts = [
    25
    53
    80
    143
    443
    465
    587
    993
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
