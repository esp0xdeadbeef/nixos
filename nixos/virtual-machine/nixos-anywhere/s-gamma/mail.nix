{ config
, lib
, mailboxSets
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
  mailRetentionService = "${hostName}-mail-retention";
  runtimeSopsFile = ../../../../secrets/s-gamma-runtime.yaml;
  retentionMaxDays = config.local.mail.mailboxSets.retention.maxDays;

  runtimeRoot = "/run/${hostName}";
  postfixRuntimeDir = "${runtimeRoot}/mail/postfix";
  dovecotRuntimeDir = "${runtimeRoot}/mail/dovecot";
  mailTlsFullchainPath = config.sGamma.certs.mail.fullchainPath;
  mailTlsKeyPath = config.sGamma.certs.mail.keyPath;
  sharedSenderLoginMap = "${postfixRuntimeDir}/shared-vaccounts";

  mailEnvPath = config.sops.secrets."mail/server/env".path;
  networkAddressEnvPath = config.sops.secrets."network/address_env".path;
  mailSecretEnvRefs = mailboxSets.envSecretRefs;
  mailboxSetEnvPaths = mailboxSetEnvPathsConfig.paths;
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailboxSetEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${hostName}-mailbox-set-env-paths";
    secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
  };
  mailAccountEnvPaths = mailAccountEnvPathsConfig.paths;
  mailAccountEnvPathList = mailAccountEnvPathsConfig.pathList;
  mailAccountEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${hostName}-mail-account-env-paths";
    secretRefs = mailboxSets.mailAccountEnvSecretRefs;
  };

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
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
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

      bool_true() {
        case "''${1:-}" in
          1|true|yes|on) return 0 ;;
          *) return 1 ;;
        esac
      }

      account_env_path() {
        account_ref="$1"
        secret_name="mail/accounts/$account_ref/env"

        awk -F= -v secret_name="$secret_name" '
          $1 == secret_name {
            print substr($0, length($1) + 2)
            found = 1
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$mail_account_env_path_list"
      }

      unset_account_vars() {
        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER LABEL DISPLAY_NAME FROM SOURCE OUTGOING USERNAME IMAP_HOST SMTP_HOST MAIL_HOST RETENTION_DAYS RETENTION_MAILBOXES; do
          unset "MAIL_ACCOUNT_$field"
        done
      }

      load_account_env() {
        account_ref="$1"
        account_path="$(account_env_path "$account_ref")" || {
          echo "mail account secret is not declared for this server: $account_ref" >&2
          exit 1
        }

        if [ ! -r "$account_path" ]; then
          echo "mail account env is missing: $account_path" >&2
          exit 1
        fi

        unset_account_vars
        set -a
        # shellcheck disable=SC1090
        . "$account_path"
        set +a
      }

      account_var() {
        field="$1"
        printenv "MAIL_ACCOUNT_$field" || true
      }

      account_address() {
        domain="$1"
        account_ref="$2"
        localpart="$(account_var LOCALPART)"

        if [ -z "$localpart" ]; then
          echo "mail account is missing LOCALPART: $account_ref" >&2
          exit 1
        fi

        printf '%s@%s\n' "$localpart" "$domain"
      }

      expand_address() {
        domain="$1"
        value="$2"

        case "$value" in
          *@*) printf '%s\n' "$value" ;;
          *) printf '%s@%s\n' "$value" "$domain" ;;
        esac
      }

      write_address_domain() {
        address="$1"
        output="$2"
        domain="''${address#*@}"

        if [ -n "$domain" ] && [ "$domain" != "$address" ]; then
          printf '%s\n' "$domain" >> "$output"
        fi
      }

      require_env MAIL_FQDN
      require_env PUBLIC_IPV4
      require_env WEB_IPV6

      install -d -m 0750 -o root -g postfix "$postfix_dir"
      install -d -m 0750 -o root -g dovecot2 "$dovecot_dir"

      vdomains="$postfix_dir/vdomains"
      vdomains_raw="$postfix_dir/vdomains.raw"
      valias_domains="$postfix_dir/valias_domains"
      valias_domains_raw="$postfix_dir/valias_domains.raw"
      valias="$postfix_dir/valias"
      vaccounts_raw="$postfix_dir/vaccounts.raw"
      vaccounts="$postfix_dir/vaccounts"
      shared_vaccounts=${lib.escapeShellArg sharedSenderLoginMap}
      passwd_file="$dovecot_dir/passwd"

      : > "$vdomains"
      : > "$vdomains_raw"
      : > "$valias_domains"
      : > "$valias_domains_raw"
      : > "$valias"
      : > "$vaccounts_raw"
      : > "$vaccounts"
      : > "$shared_vaccounts"
      : > "$passwd_file"

      first_domain=""

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        mailbox_set_path="''${entry#*=}"

        if [ ! -r "$mailbox_set_path" ]; then
          echo "mailbox set env is missing: $mailbox_set_path" >&2
          exit 1
        fi

        unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS
        set -a
        # shellcheck disable=SC1090
        . "$mailbox_set_path"
        set +a

        domain="''${MAILBOX_DOMAIN:-}"
        account_ids="''${MAILBOX_ACCOUNTS:-}"

        if [ -z "$domain" ]; then
          echo "mailbox set is missing MAILBOX_DOMAIN: $mailbox_set_path" >&2
          exit 1
        fi
        if [ -z "$account_ids" ]; then
          echo "mailbox set is missing MAILBOX_ACCOUNTS: $mailbox_set_path" >&2
          exit 1
        fi
        if [ -z "$first_domain" ]; then
          first_domain="$domain"
        fi

        printf '%s\n' "$domain" >> "$vdomains_raw"

        for account_ref in $(words "$account_ids"); do
          [ -n "$account_ref" ] || continue

          load_account_env "$account_ref"
          if ! bool_true "''${MAIL_ACCOUNT_SERVER:-true}"; then
            unset_account_vars
            continue
          fi

          address="$(account_address "$domain" "$account_ref")"
          aliases="$(account_var ALIASES)"
          password="$(account_var PASSWORD)"

          if [ -z "$password" ]; then
            echo "mail account is missing PASSWORD: $account_ref" >&2
            exit 1
          fi

          password_hash="$(doveadm pw -s BLF-CRYPT -p "$password")"
          unset password

          printf '%s %s\n' "$address" "$address" >> "$valias"
          printf '%s %s\n' "$address" "$address" >> "$vaccounts_raw"
          printf '%s:%s::::::\n' "$address" "$password_hash" >> "$passwd_file"

          for alias in $(words "$aliases"); do
            [ -n "$alias" ] || continue
            alias_address="$(expand_address "$domain" "$alias")"
            write_address_domain "$alias_address" "$valias_domains_raw"
            printf '%s %s\n' "$alias_address" "$address" >> "$valias"
            printf '%s %s\n' "$alias_address" "$address" >> "$vaccounts_raw"
          done

          unset_account_vars
        done
      done < "$mailbox_set_env_path_list"

      if [ -z "$first_domain" ]; then
        echo "no mailbox set domains were configured" >&2
        exit 1
      fi

      awk '
        NF && !seen[$1]++ {
          print $1, "OK"
        }
      ' "$vdomains_raw" > "$vdomains"

      awk '
        NR == FNR {
          if (NF) {
            mailbox[$1] = 1
          }
          next
        }

        NF && !($1 in mailbox) && !seen[$1]++ {
          print $1, "OK"
        }
      ' "$vdomains_raw" "$valias_domains_raw" > "$valias_domains"

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

      rm -f "$vdomains_raw" "$valias_domains_raw" "$vaccounts_raw"
      chown root:postfix "$vdomains" "$valias_domains" "$valias" "$vaccounts" "$shared_vaccounts"
      chmod 0640 "$vdomains" "$valias_domains" "$valias" "$vaccounts" "$shared_vaccounts"
      chown root:dovecot2 "$passwd_file"
      chmod 0440 "$passwd_file"

      postmap "$vdomains"
      postmap "$valias_domains"
      postmap "$valias"
      postmap "$vaccounts"
      postmap "$shared_vaccounts"
      chown root:postfix "$vdomains.db" "$valias_domains.db" "$valias.db" "$vaccounts.db" "$shared_vaccounts.db"
      chmod 0640 "$vdomains.db" "$valias_domains.db" "$valias.db" "$vaccounts.db" "$shared_vaccounts.db"

      main_cf=/var/lib/postfix/conf/main.cf
      if [ -L "$main_cf" ]; then
        cp --remove-destination "$(readlink -f "$main_cf")" "$main_cf"
      fi

      postconf -c /var/lib/postfix/conf -e \
        "myhostname = $MAIL_FQDN" \
        "mydomain = $first_domain" \
        "myorigin = $first_domain" \
        "smtp_bind_address = $PUBLIC_IPV4" \
        "smtp_bind_address6 = $WEB_IPV6" \
        "smtp_helo_name = $MAIL_FQDN" \
        "smtpd_banner = $MAIL_FQDN ESMTP" \
        "virtual_mailbox_domains = hash:$vdomains" \
        "virtual_alias_domains = hash:$valias_domains" \
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
      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
      shared_sender_logins=${lib.escapeShellArg sharedSenderLoginMap}
      shared_namespace_prefix=shared
      vmail_root=/var/vmail
      shared_sender_logins_raw="$shared_sender_logins.raw"
      trap 'rm -f "$shared_sender_logins_raw"' EXIT

      words() {
        local input="''${1:-}"
        printf '%s\n' "$input" | tr ',\t\r\n' ' '
      }

      shared_var() {
        local shared_id="$1"
        local field="$2"
        printenv "MAIL_SHARED_''${shared_id}_''${field}" || true
      }

      bool_true() {
        case "''${1:-}" in
          1|true|yes|on) return 0 ;;
          *) return 1 ;;
        esac
      }

      account_env_path() {
        local account_ref="$1"
        local secret_name="mail/accounts/$account_ref/env"

        awk -F= -v secret_name="$secret_name" '
          $1 == secret_name {
            print substr($0, length($1) + 2)
            found = 1
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$mail_account_env_path_list"
      }

      unset_account_vars() {
        local field

        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER LABEL DISPLAY_NAME FROM SOURCE OUTGOING USERNAME IMAP_HOST SMTP_HOST MAIL_HOST RETENTION_DAYS RETENTION_MAILBOXES; do
          unset "MAIL_ACCOUNT_$field"
        done
      }

      load_account_env() {
        local account_ref="$1"
        local account_path

        account_path="$(account_env_path "$account_ref")" || return 1
        [ -r "$account_path" ] || return 1

        unset_account_vars
        set -a
        # shellcheck disable=SC1090
        . "$account_path"
        set +a
      }

      account_var() {
        local field="$1"
        printenv "MAIL_ACCOUNT_$field" || true
      }

      account_address() {
        local domain="$1"
        local account_ref="$2"
        local localpart
        localpart="$(account_var LOCALPART)"

        if [ -z "$localpart" ]; then
          return 1
        fi

        printf '%s@%s\n' "$localpart" "$domain"
      }

      load_mailbox_users() {
        client_users=()
        owner_users=()
        all_users=()

        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          mailbox_set_path="''${entry#*=}"
          [ -r "$mailbox_set_path" ] || continue

          unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS
          set -a
          # shellcheck disable=SC1090
          . "$mailbox_set_path"
          set +a

          domain="''${MAILBOX_DOMAIN:-}"
          account_ids="''${MAILBOX_ACCOUNTS:-}"
          [ -n "$domain" ] || continue

          for account_ref in $(words "$account_ids"); do
            [ -n "$account_ref" ] || continue
            load_account_env "$account_ref" || continue
            if ! bool_true "''${MAIL_ACCOUNT_SERVER:-true}"; then
              unset_account_vars
              continue
            fi

            user="$(account_address "$domain" "$account_ref" || true)"
            [ -n "$user" ] || continue

            all_users+=("$user")
            if bool_true "$(account_var CLIENT)"; then
              client_users+=("$user")
            else
              owner_users+=("$user")
            fi

            unset_account_vars
          done
        done < "$mailbox_set_env_path_list"
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
        local owner="$1"
        local owner_local="''${owner%@*}"
        local owner_domain="''${owner#*@}"

        if [ -z "$owner_local" ] || [ -z "$owner_domain" ] || [ "$owner_domain" = "$owner" ]; then
          return 1
        fi

        printf '%s\n' "$owner_local"
      }

      shared_mailbox_name() {
        local owner="$1"
        local mailbox="$2"
        local owner_domain="''${owner#*@}"
        local owner_local
        local owner_prefix
        owner_local="$(owner_localpart "$owner")"

        if [ -z "$owner_domain" ] || [ "$owner_domain" = "$owner" ]; then
          return 1
        fi

        if [ -n "$shared_namespace_prefix" ]; then
          owner_prefix="$shared_namespace_prefix/$owner_domain/$owner_local"
        else
          owner_prefix="$owner_domain/$owner_local"
        fi

        case "$mailbox" in
          ""|INBOX)
            printf '%s/INBOX\n' "$owner_prefix"
            ;;
          INBOX/*)
            printf '%s/%s\n' "$owner_prefix" "''${mailbox#INBOX/}"
            ;;
          *)
            printf '%s/%s\n' "$owner_prefix" "$mailbox"
            ;;
        esac
      }

      right_list_has_post() {
        local rights="$1"
        local right

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
        local owner="$1"
        local user="$2"
        local rights="$3"

        if right_list_has_post "$rights"; then
          printf '%s %s\n' "$owner" "$user" >> "$shared_sender_logins_raw"
        fi
      }

      subscriptions_file_for_user() {
        local user="$1"
        local user_local
        local user_domain="''${user#*@}"
        user_local="$(owner_localpart "$user")"

        printf '%s/%s/%s/mail/subscriptions\n' "$vmail_root" "$user_domain" "$user_local"
      }

      remove_managed_subscriptions() {
        local subscriptions_file="$1"
        local managed_domain
        local managed_domains
        local managed_user
        local tmp

        [ -f "$subscriptions_file" ] || return 0

        managed_domains="$(
          for managed_user in "''${all_users[@]}"; do
            managed_domain="''${managed_user#*@}"
            if [ -n "$managed_domain" ] && [ "$managed_domain" != "$managed_user" ]; then
              printf '%s\n' "$managed_domain"
            fi
          done | sort -u | tr '\n' ' '
        )"

        tmp="$(mktemp "''${subscriptions_file}.tmp.XXXXXX")"
        awk -v current="$shared_namespace_prefix" -v managed_domains="$managed_domains" '
          BEGIN {
            split(managed_domains, domains, " ")
          }

          {
            keep = 1
            prefixes[1] = "shared"
            prefixes[2] = "users"
            prefixes[3] = current

            for (i = 1; i <= 3; i++) {
              prefix = prefixes[i]
              if (prefix != "" && ($0 == prefix || index($0, prefix "/") == 1 || index($0, prefix "\t") == 1)) {
                keep = 0
                break
              }
            }

            for (i in domains) {
              domain = domains[i]
              if (domain != "" && ($0 == domain || index($0, domain "/") == 1 || index($0, domain "\t") == 1)) {
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
        for user in "''${all_users[@]}"; do
          subscriptions_file="$(subscriptions_file_for_user "$user" || true)"
          [ -n "$subscriptions_file" ] || continue
          remove_managed_subscriptions "$subscriptions_file"
        done
      }

      sync_automatic_account_mailboxes() {
        mailbox="''${MAIL_SHARED_AUTO_MAILBOX:-INBOX}"
        rights="''${MAIL_SHARED_AUTO_RIGHTS:-lookup read write write-seen write-deleted insert post expunge create delete}"

        [ "''${#owner_users[@]}" -ne 0 ] || return 0
        [ "''${#client_users[@]}" -ne 0 ] || return 0
        [ -n "$mailbox" ] || mailbox=INBOX

        rights_args=()
        for right in $(words "$rights"); do
          [ -n "$right" ] || continue
          rights_args+=("$right")
        done

        for owner in "''${owner_users[@]}"; do
          if ! doveadm user "$owner" >/dev/null 2>&1; then
            echo "shared-mail-subscriptions: automatic owner is not a Dovecot user: $owner" >&2
            continue
          fi

          if ! doveadm mailbox status -u "$owner" uidvalidity "$mailbox" >/dev/null 2>&1; then
            doveadm mailbox create -u "$owner" -s "$mailbox" >/dev/null 2>&1 || true
          fi

          visible_mailbox="$(shared_mailbox_name "$owner" "$mailbox")"

          for cleanup_user in "''${all_users[@]}"; do
            [ "$cleanup_user" != "$owner" ] || continue

            doveadm acl remove -u "$owner" "$mailbox" "user=$cleanup_user" >/dev/null 2>&1 || true
          done
          doveadm acl recalc -u "$owner" >/dev/null

          for user in "''${client_users[@]}"; do
            [ "$user" != "$owner" ] || continue

            if ! doveadm user "$user" >/dev/null 2>&1; then
              echo "shared-mail-subscriptions: automatic ACL user is not a Dovecot user: $user" >&2
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

          owner="$owner_ref"
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
            user="$user_ref"

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
        local user="$1"
        local mailbox="$2"

        if ! doveadm user "$user" >/dev/null 2>&1; then
          return 0
        fi

        if ! doveadm acl debug -u "$user" "$mailbox" >/dev/null 2>&1; then
          echo "shared-mail-subscriptions: mailbox is not visible for ACL user: user=$user mailbox=$mailbox" >&2
          return 1
        fi

        doveadm mailbox subscribe -u "$user" "$mailbox" >/dev/null
      }

      sync_visible_shared_subscriptions() {
        local user
        local visible_mailbox

        [ -n "$shared_namespace_prefix" ] || return 0

        for user in "''${client_users[@]}"; do
          if ! doveadm user "$user" >/dev/null 2>&1; then
            continue
          fi

          while IFS= read -r visible_mailbox; do
            [ -n "$visible_mailbox" ] || continue

            case "$visible_mailbox" in
              "$shared_namespace_prefix"/*)
                if subscribe_user "$user" "$visible_mailbox"; then
                  subscribed=$((subscribed + 1))
                else
                  failed=$((failed + 1))
                fi
                ;;
            esac
          done < <(doveadm mailbox list -u "$user")
        done
      }

      subscribed=0
      failed=0
      : > "$shared_sender_logins_raw"

      load_mailbox_users
      clear_managed_subscriptions
      sync_automatic_account_mailboxes
      sync_declared_shared_mailboxes
      sync_visible_shared_subscriptions

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

  applyMailRetention = pkgs.writeShellApplication {
    name = "${hostName}-apply-mail-retention";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dovecot
      pkgs.gawk
    ];
    text = ''
      set -euo pipefail

      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
      retention_max_days=${lib.escapeShellArg (toString retentionMaxDays)}

      words() {
        local input="''${1:-}"
        printf '%s\n' "$input" | tr ',\t\r\n' ' '
      }

      bool_true() {
        case "''${1:-}" in
          1|true|yes|on) return 0 ;;
          *) return 1 ;;
        esac
      }

      account_env_path() {
        local account_ref="$1"
        local secret_name="mail/accounts/$account_ref/env"

        awk -F= -v secret_name="$secret_name" '
          $1 == secret_name {
            print substr($0, length($1) + 2)
            found = 1
          }

          END {
            exit(found ? 0 : 1)
          }
        ' "$mail_account_env_path_list"
      }

      unset_account_vars() {
        local field

        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER LABEL DISPLAY_NAME FROM SOURCE OUTGOING USERNAME IMAP_HOST SMTP_HOST MAIL_HOST RETENTION_DAYS RETENTION_MAILBOXES; do
          unset "MAIL_ACCOUNT_$field"
        done
      }

      load_account_env() {
        local account_ref="$1"
        local account_path

        account_path="$(account_env_path "$account_ref")" || return 1
        [ -r "$account_path" ] || return 1

        unset_account_vars
        set -a
        # shellcheck disable=SC1090
        . "$account_path"
        set +a
      }

      account_var() {
        local field="$1"
        printenv "MAIL_ACCOUNT_$field" || true
      }

      account_address() {
        local domain="$1"
        local account_ref="$2"
        local localpart
        localpart="$(account_var LOCALPART)"

        if [ -z "$localpart" ]; then
          echo "mail-retention: account is missing LOCALPART: $account_ref" >&2
          return 1
        fi

        printf '%s@%s\n' "$localpart" "$domain"
      }

      effective_retention_days() {
        local account_ref="$1"
        local configured_days="$2"

        if [ -z "$configured_days" ]; then
          return 1
        fi

        case "$configured_days" in
          *[!0-9]*|0)
            echo "mail-retention: invalid MAIL_ACCOUNT_RETENTION_DAYS for $account_ref: $configured_days" >&2
            return 2
            ;;
        esac

        if [ "$configured_days" -gt "$retention_max_days" ]; then
          echo "mail-retention: capping $account_ref retention from $configured_days to $retention_max_days day(s)" >&2
          printf '%s\n' "$retention_max_days"
        else
          printf '%s\n' "$configured_days"
        fi
      }

      expunge_mailbox() {
        local user="$1"
        local mailbox="$2"
        local retention_days="$3"

        [ -n "$mailbox" ] || return 0
        doveadm expunge -u "$user" mailbox "$mailbox" savedbefore "''${retention_days}d"
      }

      apply_account_retention() {
        local account_ref="$1"
        local domain="$2"
        local configured_days
        local retention_days
        local user
        local mailbox
        local mailbox_count=0
        local configured_mailboxes

        configured_days="$(account_var RETENTION_DAYS)"
        retention_days="$(effective_retention_days "$account_ref" "$configured_days")" || return 0
        user="$(account_address "$domain" "$account_ref")" || return 1

        if ! doveadm user "$user" >/dev/null 2>&1; then
          echo "mail-retention: skipping unknown Dovecot user: $user" >&2
          return 0
        fi

        configured_mailboxes="$(account_var RETENTION_MAILBOXES)"
        if [ -n "$configured_mailboxes" ]; then
          for mailbox in $(words "$configured_mailboxes"); do
            expunge_mailbox "$user" "$mailbox" "$retention_days"
            mailbox_count=$((mailbox_count + 1))
          done
        else
          while IFS= read -r mailbox; do
            [ -n "$mailbox" ] || continue
            expunge_mailbox "$user" "$mailbox" "$retention_days"
            mailbox_count=$((mailbox_count + 1))
          done < <(doveadm mailbox list -u "$user")
        fi

        echo "mail-retention: applied $retention_days day(s) to $mailbox_count mailbox(es) for $user"
      }

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        mailbox_set_path="''${entry#*=}"
        [ -r "$mailbox_set_path" ] || continue

        unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS MAILBOX_MAIL_HOST MAILBOX_IMAP_HOST MAILBOX_SMTP_HOST MAILBOX_IMAP_PORT MAILBOX_SMTP_PORT
        set -a
        # shellcheck disable=SC1090
        . "$mailbox_set_path"
        set +a

        domain="''${MAILBOX_DOMAIN:-}"
        account_refs="''${MAILBOX_ACCOUNTS:-}"
        [ -n "$domain" ] || continue

        for account_ref in $(words "$account_refs"); do
          [ -n "$account_ref" ] || continue
          load_account_env "$account_ref" || continue

          if ! bool_true "''${MAIL_ACCOUNT_SERVER:-true}"; then
            unset_account_vars
            continue
          fi

          apply_account_retention "$account_ref" "$domain"
          unset_account_vars
        done
      done < "$mailbox_set_env_path_list"
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
          value = {
            inherit (secret) key sopsFile;
            restartUnits = [
              mailRuntimeConfigUnit
              "postfix.service"
              "dovecot.service"
            ];
          };
        })
        mailSecretEnvRefs
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
      ++ mailboxSetEnvPaths
      ++ mailAccountEnvPaths
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

  systemd.services.${mailRetentionService} = {
    description = "Apply Dovecot retention policies from SOPS mail account profiles";
    after = [
      "dovecot.service"
      mailRuntimeConfigUnit
    ];
    requires = [
      "dovecot.service"
      mailRuntimeConfigUnit
    ];
    preStart = waitForReadableFiles "mail retention" (
      mailboxSetEnvPaths ++ mailAccountEnvPaths
    );
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe applyMailRetention;
    };
  };

  systemd.timers.${mailRetentionService} = {
    description = "Run Dovecot mail retention policies";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:20:00";
      RandomizedDelaySec = "30min";
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
        prefix = "shared/$domain/$username/";
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
