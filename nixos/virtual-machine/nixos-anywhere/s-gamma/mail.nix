{ config
, lib
, name
, pkgs
, ...
}:
let
  hostName = name;
  networkAddressesUnit = "${hostName}-network-addresses.service";
  mailRuntimeConfigService = "${hostName}-mail-runtime-config";
  mailRuntimeConfigUnit = "${mailRuntimeConfigService}.service";
  rspamdRuntimeConfigService = "${hostName}-rspamd-runtime-config";
  sharedSubscriptionsService = "${hostName}-mail-shared-subscriptions";
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;
  mailAccounts = import ../../../../profiles/mail/accounts.nix {
    secretsRoot = ../../../../secrets;
  };

  runtimeRoot = "/run/${hostName}";
  postfixRuntimeDir = "${runtimeRoot}/mail/postfix";
  dovecotRuntimeDir = "${runtimeRoot}/mail/dovecot";
  mailTlsFullchainPath = config.sGamma.certs.mail.fullchainPath;
  mailTlsKeyPath = config.sGamma.certs.mail.keyPath;
  sharedSenderLoginMap = "${postfixRuntimeDir}/shared-vaccounts";

  mailEnvPath = config.sops.secrets."mail/server/env".path;
  networkAddressEnvPath = config.sops.secrets."network/address_env".path;
  mailAccountSecretRefs = lib.flatten (
    map
      (
        account:
        map (field: mailAccounts.secretRef account field) mailAccounts.serverFields
      )
      mailAccounts.serverAccountNames
  );
  mailAccountSecretPathsByName = builtins.listToAttrs (
    map
      (secret: {
        inherit (secret) name;
        value = config.sops.secrets.${secret.name}.path;
      })
      mailAccountSecretRefs
  );
  mailAccountSecretPaths = builtins.attrValues mailAccountSecretPathsByName;
  mailClientAccountIds = map
    (account: mailAccounts.accounts.${account}.serverId)
    mailAccounts.clientAccountNames;
  mailAutomaticSharedAccountIds = map
    (account: mailAccounts.accounts.${account}.serverId)
    (
      builtins.filter
        (account: !(mailAccounts.accounts.${account}.client or false))
        mailAccounts.serverAccountNames
    );
  mailAccountSecretPathMap = pkgs.writeText "${hostName}-mail-account-secret-paths" (
    (lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (
          secretName: path: "${secretName}=${path}"
        )
        mailAccountSecretPathsByName
    ))
    + "\n"
  );

  waitForReadableFiles = label: paths: ''
    for path in ${lib.concatMapStringsSep " " lib.escapeShellArg paths}; do
      until [ -r "$path" ]; do
        echo "${label}: waiting for readable file: $path" >&2
        sleep 1
      done
    done
  '';

  renderMailRuntime = pkgs.writeShellApplication {
    name = "${hostName}-render-mail-runtime";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dovecot
      pkgs.gawk
      pkgs.gnugrep
      pkgs.postfix
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      network_env_file=${lib.escapeShellArg networkAddressEnvPath}
      account_secret_path_map=${lib.escapeShellArg mailAccountSecretPathMap}
      postfix_dir=${lib.escapeShellArg postfixRuntimeDir}
      dovecot_dir=${lib.escapeShellArg dovecotRuntimeDir}
      tls_fullchain=${lib.escapeShellArg mailTlsFullchainPath}
      tls_key=${lib.escapeShellArg mailTlsKeyPath}

      if [ ! -r "$env_file" ]; then
        echo "mail runtime env is missing: $env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$env_file"
      # shellcheck disable=SC1090
      . "$network_env_file"
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

      secret_file() {
        secret="$1"

        awk -F= -v secret="$secret" '
          $1 == secret {
            print substr($0, length($1) + 2)
            found = 1
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$account_secret_path_map"
      }

      account_secret() {
        account_id="$1"
        account_secret_var="MAIL_''${account_id}_ACCOUNT_SECRET"
        account_secret="$(printenv "$account_secret_var" || true)"

        if [ -z "$account_secret" ]; then
          echo "missing account secret variable for mail account id: $account_id" >&2
          exit 1
        fi

        printf '%s\n' "$account_secret"
      }

      account_secret_file() {
        account="$1"
        field="$2"

        secret_file "$account/$field" || {
          echo "unknown mail account secret field: $account/$field" >&2
          exit 1
        }
      }

      read_required_account_field() {
        account="$1"
        field="$2"
        path="$(account_secret_file "$account" "$field")"

        if [ ! -r "$path" ]; then
          echo "mail account field is missing: $account/$field" >&2
          exit 1
        fi

        tr -d '\r\n' < "$path"
      }

      read_optional_account_field() {
        account="$1"
        field="$2"
        path="$(account_secret_file "$account" "$field")"

        [ -r "$path" ] || return 0
        tr '\t\r\n' ' ' < "$path"
      }

      require_env MAIL_FQDN
      require_env MAIL_DOMAIN
      require_env MAIL_DOMAINS
      require_env MAIL_ACCOUNTS
      require_env PUBLIC_IPV4
      require_env WEB_IPV6

      install -d -m 0750 -o root -g postfix "$postfix_dir"
      install -d -m 0750 -o root -g dovecot2 "$dovecot_dir"

      vdomains="$postfix_dir/vdomains"
      valias="$postfix_dir/valias"
      vaccounts_raw="$postfix_dir/vaccounts.raw"
      vaccounts="$postfix_dir/vaccounts"
      shared_vaccounts=${lib.escapeShellArg sharedSenderLoginMap}
      passwd_file="$dovecot_dir/passwd"

      : > "$vdomains"
      : > "$valias"
      : > "$vaccounts_raw"
      : > "$vaccounts"
      : > "$shared_vaccounts"
      : > "$passwd_file"

      for domain in $(words "$MAIL_DOMAINS"); do
        [ -n "$domain" ] || continue
        printf '%s OK\n' "$domain" >> "$vdomains"
      done

      for account_id in $(words "$MAIL_ACCOUNTS"); do
        [ -n "$account_id" ] || continue

        account="$(account_secret "$account_id")"
        address="$(read_required_account_field "$account" username)"
        aliases="$(read_optional_account_field "$account" aliases)"
        password_file="$(account_secret_file "$account" password)"

        if [ -z "$address" ]; then
          echo "empty username for mail account id: $account_id" >&2
          exit 1
        fi

        if [ ! -r "$password_file" ]; then
          echo "mail password is missing for account id: $account_id" >&2
          exit 1
        fi

        password="$(tr -d '\r\n' < "$password_file")"
        password_hash="$(doveadm pw -s BLF-CRYPT -p "$password")"
        unset password

        printf '%s %s\n' "$address" "$address" >> "$valias"
        printf '%s %s\n' "$address" "$address" >> "$vaccounts_raw"
        printf '%s:%s::::::\n' "$address" "$password_hash" >> "$passwd_file"

        for alias in $(words "$aliases"); do
          [ -n "$alias" ] || continue
          printf '%s %s\n' "$alias" "$address" >> "$valias"
          printf '%s %s\n' "$alias" "$address" >> "$vaccounts_raw"
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
      chown root:postfix "$vdomains" "$valias" "$vaccounts" "$shared_vaccounts"
      chmod 0640 "$vdomains" "$valias" "$vaccounts" "$shared_vaccounts"
      chown root:dovecot2 "$passwd_file"
      chmod 0440 "$passwd_file"

      postmap "$vdomains"
      postmap "$valias"
      postmap "$vaccounts"
      postmap "$shared_vaccounts"
      chown root:postfix "$vdomains.db" "$valias.db" "$vaccounts.db" "$shared_vaccounts.db"
      chmod 0640 "$vdomains.db" "$valias.db" "$vaccounts.db" "$shared_vaccounts.db"

      main_cf=/var/lib/postfix/conf/main.cf
      if [ -L "$main_cf" ]; then
        cp --remove-destination "$(readlink -f "$main_cf")" "$main_cf"
      fi

      postconf -c /var/lib/postfix/conf -e \
        "myhostname = $MAIL_FQDN" \
        "mydomain = $MAIL_DOMAIN" \
        "myorigin = $MAIL_DOMAIN" \
        "smtp_bind_address = $PUBLIC_IPV4" \
        "smtp_bind_address6 = $WEB_IPV6" \
        "smtp_helo_name = $MAIL_FQDN" \
        "smtpd_banner = $MAIL_FQDN ESMTP" \
        "virtual_mailbox_domains = hash:$vdomains" \
        "virtual_mailbox_maps = hash:$valias" \
        "virtual_alias_maps = hash:$valias" \
        "smtpd_sender_login_maps = hash:$vaccounts hash:$shared_vaccounts" \
        "smtpd_tls_chain_files = $tls_key $tls_fullchain"

      postfix -c /var/lib/postfix/conf check
    '';
  };

  syncSharedMailSubscriptions = pkgs.writeShellApplication {
    name = "${hostName}-sync-shared-mail-subscriptions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dovecot
      pkgs.gawk
      pkgs.gnugrep
      pkgs.postfix
    ];
    text = ''
      set -euo pipefail

      env_file=${lib.escapeShellArg mailEnvPath}
      account_secret_path_map=${lib.escapeShellArg mailAccountSecretPathMap}
      automatic_client_account_ids=${lib.escapeShellArg (lib.concatStringsSep " " mailClientAccountIds)}
      automatic_shared_account_ids=${lib.escapeShellArg (lib.concatStringsSep " " mailAutomaticSharedAccountIds)}
      shared_sender_logins=${lib.escapeShellArg sharedSenderLoginMap}
      shared_namespace_prefix=users
      vmail_root=/var/vmail
      shared_sender_logins_raw="$shared_sender_logins.raw"
      trap 'rm -f "$shared_sender_logins_raw"' EXIT

      words() {
        printf '%s\n' "''${1:-}" | tr ',\t\r\n' ' '
      }

      secret_file() {
        secret="$1"

        awk -F= -v secret="$secret" '
          $1 == secret {
            print substr($0, length($1) + 2)
            found = 1
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$account_secret_path_map"
      }

      account_secret_for_ref() {
        ref="$1"
        account_secret_var="MAIL_''${ref}_ACCOUNT_SECRET"
        printenv "$account_secret_var" || true
      }

      read_account_field() {
        account="$1"
        field="$2"
        path="$(secret_file "$account/$field")" || return 1

        [ -r "$path" ] || return 1
        tr -d '\r\n' < "$path"
      }

      ref_to_address() {
        ref="$1"
        account="$(account_secret_for_ref "$ref")"
        if [ -n "$account" ]; then
          read_account_field "$account" username
          return
        fi

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

      owner_localpart() {
        owner="$1"
        owner_local="''${owner%@*}"
        owner_domain="''${owner#*@}"

        if [ -z "$owner_local" ] || [ -z "$owner_domain" ] || [ "$owner_domain" = "$owner" ]; then
          return 1
        fi

        printf '%s\n' "$owner_local"
      }

      shared_mailbox_name() {
        owner="$1"
        mailbox="$2"
        owner_local="$(owner_localpart "$owner")"

        case "$mailbox" in
          ""|INBOX)
            printf '%s/%s/INBOX\n' "$shared_namespace_prefix" "$owner_local"
            ;;
          INBOX/*)
            printf '%s/%s/%s\n' "$shared_namespace_prefix" "$owner_local" "''${mailbox#INBOX/}"
            ;;
          *)
            printf '%s/%s/%s\n' "$shared_namespace_prefix" "$owner_local" "$mailbox"
            ;;
        esac
      }

      right_list_has_post() {
        rights="$1"

        for right in $(words "$rights"); do
          case "$right" in
            p|post)
              return 0
              ;;
          esac

          if ! printf '%s\n' "$right" | grep -Eq '^(lookup|read|write|write-seen|write-deleted|insert|post|expunge|create|delete|admin)$' \
            && printf '%s\n' "$right" | grep -Eq '^[lrwstipekxacd]+$' \
            && printf '%s\n' "$right" | grep -q p; then
            return 0
          fi
        done

        return 1
      }

      add_sender_login() {
        owner="$1"
        user="$2"
        rights="$3"

        if right_list_has_post "$rights"; then
          printf '%s %s\n' "$owner" "$user" >> "$shared_sender_logins_raw"
        fi
      }

      subscriptions_file_for_user() {
        user="$1"
        user_local="$(owner_localpart "$user")"
        user_domain="''${user#*@}"

        printf '%s/%s/%s/mail/subscriptions\n' "$vmail_root" "$user_domain" "$user_local"
      }

      remove_managed_subscriptions() {
        subscriptions_file="$1"

        [ -f "$subscriptions_file" ] || return 0

        tmp="$(mktemp "''${subscriptions_file}.tmp.XXXXXX")"
        awk -v current="$shared_namespace_prefix" '
          {
            keep = 1
            prefixes[1] = "shared"
            prefixes[2] = current

            for (i = 1; i <= 2; i++) {
              prefix = prefixes[i]
              if ($0 == prefix || index($0, prefix "/") == 1 || index($0, prefix "\t") == 1) {
                keep = 0
                break
              }
            }

            if (keep) {
              print
            }
          }
        ' "$subscriptions_file" > "$tmp"
        chown --reference="$subscriptions_file" "$tmp"
        chmod --reference="$subscriptions_file" "$tmp"
        mv "$tmp" "$subscriptions_file"
      }

      clear_managed_subscriptions() {
        for account_id in $(words "''${MAIL_ACCOUNTS:-} $automatic_client_account_ids $automatic_shared_account_ids"); do
          [ -n "$account_id" ] || continue
          user="$(ref_to_address "$account_id" || true)"
          [ -n "$user" ] || continue

          subscriptions_file="$(subscriptions_file_for_user "$user" || true)"
          [ -n "$subscriptions_file" ] || continue
          remove_managed_subscriptions "$subscriptions_file"
        done
      }

      sync_automatic_account_mailboxes() {
        owner_refs="''${MAIL_SHARED_AUTO_OWNERS:-$automatic_shared_account_ids}"
        user_refs="''${MAIL_SHARED_AUTO_USERS:-$automatic_client_account_ids}"
        mailbox="''${MAIL_SHARED_AUTO_MAILBOX:-INBOX}"
        rights="''${MAIL_SHARED_AUTO_RIGHTS:-lookup read write write-seen write-deleted insert post expunge create delete}"

        [ -n "$owner_refs" ] || return 0
        [ -n "$user_refs" ] || return 0
        [ -n "$mailbox" ] || mailbox=INBOX

        rights_args=()
        for right in $(words "$rights"); do
          [ -n "$right" ] || continue
          rights_args+=("$right")
        done

        for owner_ref in $(words "$owner_refs"); do
          [ -n "$owner_ref" ] || continue
          owner="$(ref_to_address "$owner_ref")"

          if ! doveadm user "$owner" >/dev/null 2>&1; then
            echo "shared-mail-subscriptions: automatic owner is not a Dovecot user: $owner_ref" >&2
            continue
          fi

          if ! doveadm mailbox status -u "$owner" uidvalidity "$mailbox" >/dev/null 2>&1; then
            doveadm mailbox create -u "$owner" -s "$mailbox" >/dev/null 2>&1 || true
          fi

          visible_mailbox="$(shared_mailbox_name "$owner" "$mailbox")"

          for cleanup_ref in $(words "''${MAIL_ACCOUNTS:-} $automatic_client_account_ids $automatic_shared_account_ids $user_refs"); do
            [ -n "$cleanup_ref" ] || continue
            [ "$cleanup_ref" != "$owner_ref" ] || continue
            cleanup_user="$(ref_to_address "$cleanup_ref" || true)"
            [ -n "$cleanup_user" ] || continue
            [ "$cleanup_user" != "$owner" ] || continue

            doveadm acl remove -u "$owner" "$mailbox" "user=$cleanup_user" >/dev/null 2>&1 || true
          done
          doveadm acl recalc -u "$owner" >/dev/null

          for user_ref in $(words "$user_refs"); do
            [ -n "$user_ref" ] || continue
            [ "$user_ref" != "$owner_ref" ] || continue
            user="$(ref_to_address "$user_ref")"
            [ "$user" != "$owner" ] || continue

            if ! doveadm user "$user" >/dev/null 2>&1; then
              echo "shared-mail-subscriptions: automatic ACL user is not a Dovecot user: $user_ref" >&2
              continue
            fi

            doveadm acl add -u "$owner" "$mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
            doveadm acl recalc -u "$owner" >/dev/null
            add_sender_login "$owner" "$user" "$rights"

            if subscribe_user "$user" "$visible_mailbox"; then
              subscribed=$((subscribed + 1))
            else
              failed=$((failed + 1))
            fi
          done
        done
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

          visible_mailbox="$(shared_mailbox_name "$owner" "$mailbox")"

          for user_ref in $(words "$user_refs"); do
            [ -n "$user_ref" ] || continue
            user="$(ref_to_address "$user_ref")"

            if ! doveadm user "$user" >/dev/null 2>&1; then
              echo "shared-mail-subscriptions: ACL user is not a Dovecot user: $user_ref" >&2
              continue
            fi

            doveadm acl add -u "$owner" "$mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
            doveadm acl recalc -u "$owner" >/dev/null
            add_sender_login "$owner" "$user" "$rights"

            if subscribe_user "$user" "$visible_mailbox"; then
              subscribed=$((subscribed + 1))
            else
              failed=$((failed + 1))
            fi
          done
        done
      }

      subscribe_user() {
        user="$1"
        mailbox="$2"

        if ! doveadm user "$user" >/dev/null 2>&1; then
          return 0
        fi

        if ! doveadm acl debug -u "$user" "$mailbox" >/dev/null 2>&1; then
          echo "shared-mail-subscriptions: mailbox is not visible for ACL user: user=$user mailbox=$mailbox" >&2
          return 1
        fi

        doveadm mailbox subscribe -u "$user" "$mailbox" >/dev/null
      }

      subscribed=0
      failed=0
      : > "$shared_sender_logins_raw"

      clear_managed_subscriptions
      sync_automatic_account_mailboxes
      sync_declared_shared_mailboxes

      awk '
        {
          sender = $1
          login = $2

          if (sender == "" || login == "") {
            next
          }

          if (!(sender in seen_sender)) {
            seen_sender[sender] = 1
            sender_order[++sender_count] = sender
          }

          key = sender SUBSEP login
          if (!(key in seen_login)) {
            seen_login[key] = 1
            login_list[sender] = login_list[sender] (login_list[sender] == "" ? "" : ",") login
          }
        }

        END {
          for (i = 1; i <= sender_count; i++) {
            sender = sender_order[i]
            print sender, login_list[sender]
          }
        }
      ' "$shared_sender_logins_raw" > "$shared_sender_logins"

      rm -f "$shared_sender_logins_raw"
      chown root:postfix "$shared_sender_logins"
      chmod 0640 "$shared_sender_logins"
      postmap "$shared_sender_logins"
      chown root:postfix "$shared_sender_logins.db"
      chmod 0640 "$shared_sender_logins.db"

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
    smtpd_sender_restrictions = "reject_sender_login_mismatch";
    smtpd_recipient_restrictions = "reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject";
    milter_macro_daemon_name = "ORIGINATING";
  };

  postfixTls12CipherList = lib.concatStringsSep ":" [
    "ECDHE-ECDSA-AES256-GCM-SHA384"
    "ECDHE-ECDSA-CHACHA20-POLY1305"
    "ECDHE-ECDSA-AES128-GCM-SHA256"
    "@STRENGTH"
    "@SECLEVEL=2"
  ];
in
{
  users.groups.virtualMail = { };
  users.users.virtualMail = {
    isSystemUser = true;
    group = "virtualMail";
    home = "/var/vmail";
  };

  sops.secrets =
    {
      "mail/server/env" = {
        sopsFile = runtimeSopsFile;
        restartUnits = [
          mailRuntimeConfigUnit
          "postfix.service"
          "dovecot.service"
        ];
      };
    }
    // builtins.listToAttrs (
      map
        (secret: {
          inherit (secret) name;
          value.sopsFile = secret.sopsFile;
        })
        mailAccountSecretRefs
    );

  systemd.tmpfiles.rules = [
    "d ${runtimeRoot} 0755 root root -"
    "d ${runtimeRoot}/mail 0755 root root -"
    "d ${postfixRuntimeDir} 0750 root postfix -"
    "d ${dovecotRuntimeDir} 0750 root dovecot2 -"
    "d /var/lib/postfix/data 0700 postfix postfix -"
    "z /var/lib/postfix/data 0700 postfix postfix -"
    "z /var/lib/postfix/data/master.lock 0600 postfix postfix -"
    "z /var/lib/postfix/data/prng_exch 0600 postfix postfix -"
    "d /var/vmail 0750 virtualMail virtualMail -"
    "d /var/lib/dovecot 0755 root root -"
    "d /var/lib/dovecot/db 0770 virtualMail virtualMail -"
    "Z /var/lib/dovecot/db - virtualMail virtualMail -"
  ];

  systemd.services.${mailRuntimeConfigService} = {
    description = "Render ${hostName} mail runtime maps from SOPS";
    after = [
      "postfix-setup.service"
      networkAddressesUnit
    ];
    requires = [
      "postfix-setup.service"
      networkAddressesUnit
    ];
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
    preStart = waitForReadableFiles "mail runtime" (
      [
        networkAddressEnvPath
        mailEnvPath
        mailTlsFullchainPath
        mailTlsKeyPath
      ]
      ++ mailAccountSecretPaths
    );
    script = "${lib.getExe renderMailRuntime}";
  };

  systemd.services.${rspamdRuntimeConfigService} = {
    description = "Prepare ${hostName} rspamd runtime files";
    before = [ "rspamd.service" ];
    requiredBy = [ "rspamd.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      install -d -m 0755 -o root -g root /var/dkim

      found=0
      for key in /var/dkim/*.key; do
        [ -e "$key" ] || continue
        found=1
        chown rspamd:rspamd "$key"
        chmod 0400 "$key"
      done

      if [ "$found" -eq 0 ]; then
        echo "rspamd: no DKIM key found in /var/dkim" >&2
        exit 1
      fi
    '';
  };

  systemd.services.postfix = {
    after = [
      "dovecot.service"
      "rspamd.service"
      mailRuntimeConfigUnit
    ];
    requires = [
      "dovecot.service"
      mailRuntimeConfigUnit
    ];
    wants = [ "rspamd.service" ];
  };

  systemd.services.dovecot = {
    after = [ mailRuntimeConfigUnit ];
    requires = [ mailRuntimeConfigUnit ];
  };

  systemd.services.${sharedSubscriptionsService} = {
    description = "Sync Dovecot shared mailbox ACL projections";
    after = [
      "dovecot.service"
      mailRuntimeConfigUnit
    ];
    requires = [
      "dovecot.service"
      mailRuntimeConfigUnit
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe syncSharedMailSubscriptions;
    };
  };

  systemd.timers.${sharedSubscriptionsService} = {
    description = "Refresh Dovecot shared mailbox ACL projections";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      AccuracySec = "15s";
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
        mailTlsKeyPath
        mailTlsFullchainPath
      ];
      smtpd_tls_security_level = "may";
      smtpd_tls_protocols = ">=TLSv1.2";
      smtpd_tls_mandatory_protocols = ">=TLSv1.2";
      smtpd_tls_ciphers = "high";
      smtpd_tls_mandatory_ciphers = "high";

      tls_high_cipherlist = postfixTls12CipherList;
      tls_preempt_cipherlist = true;
      tls_eecdh_auto_curves = "X25519:prime256v1:secp384r1";

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

  services.rspamd = {
    enable = true;
    postfix = {
      enable = true;
      config = {
        smtpd_milters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
        non_smtpd_milters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
        milter_default_action = "accept";
        milter_protocol = "6";
      };
    };
    locals."dkim_signing.conf".text = ''
      enabled = true;
      sign_authenticated = true;
      sign_local = true;
      allow_username_mismatch = true;

      selector = "mail";
      path = "/var/dkim/$domain.$selector.key";
    '';
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
      mail_shared_explicit_inbox = false;
      acl_defaults_from_inbox = true;
      acl_driver = "vfile";

      "acl_sharing_map"."dict file".path = "/var/lib/dovecot/db/shared-mailboxes.db";

      "namespace inbox" = {
        inbox = true;
        separator = "/";
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
        separator = "/";
        prefix = "users/$username/";
        list = "yes";
        subscriptions = false;
        mail_driver = "maildir";
        mail_path = "/var/vmail/%{owner_user | domain}/%{owner_user | username}/mail";
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
      ssl_server_cert_file = mailTlsFullchainPath;
      ssl_server_key_file = mailTlsKeyPath;
      ssl_min_protocol = "TLSv1.2";
    };
  };

  networking.firewall.allowedTCPPorts = [
    25
    143
    465
    587
    993
  ];
}
