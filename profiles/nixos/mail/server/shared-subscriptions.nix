{ cfg
, hostName
, lib
, mailAccountEnvPathList
, mailEnvPath
, mailboxSetEnvPathList
, pkgs
, sharedSenderLoginMap
}:

pkgs.writeShellApplication {
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
    shared_namespace_prefix=${lib.escapeShellArg cfg.sharedNamespacePrefix}
    shared_namespace_include_domain=${lib.escapeShellArg (if cfg.sharedNamespaceIncludeDomain then "1" else "0")}
    shared_namespace_explicit_inbox=${lib.escapeShellArg (if cfg.sharedExplicitInbox then "1" else "0")}
    shared_inherit_inbox_acl=${lib.escapeShellArg (if cfg.sharedInheritInboxAcl then "1" else "0")}
    vmail_root=/var/vmail
    shared_sender_logins_raw="$shared_sender_logins.raw"
    desired_subscriptions_dir="$(mktemp -d)"
    trap 'rm -f "$shared_sender_logins_raw"; rm -rf -- "$desired_subscriptions_dir"' EXIT

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
        if [ "$shared_namespace_include_domain" = "1" ]; then
          owner_prefix="$shared_namespace_prefix/$owner_domain/$owner_local"
        else
          owner_prefix="$shared_namespace_prefix/$owner_local"
        fi
      else
        owner_prefix="$owner_domain/$owner_local"
      fi

      case "$mailbox" in
        ""|INBOX)
          if [ "$shared_namespace_explicit_inbox" = "1" ]; then
            printf '%s/INBOX\n' "$owner_prefix"
          else
            printf '%s\n' "$owner_prefix"
          fi
          ;;
        INBOX/*)
          if [ "$shared_namespace_explicit_inbox" = "1" ]; then
            printf '%s/%s\n' "$owner_prefix" "$mailbox"
          else
            printf '%s/%s\n' "$owner_prefix" "''${mailbox#INBOX/}"
          fi
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

    same_mail_domain() {
      local left="$1"
      local right="$2"
      local left_domain="''${left#*@}"
      local right_domain="''${right#*@}"

      [ -n "$left_domain" ] || return 1
      [ -n "$right_domain" ] || return 1
      [ "$left_domain" != "$left" ] || return 1
      [ "$right_domain" != "$right" ] || return 1
      [ "$left_domain" = "$right_domain" ]
    }

    subscriptions_file_for_user() {
      local user="$1"
      local user_local
      local user_domain="''${user#*@}"
      user_local="$(owner_localpart "$user")"

      printf '%s/%s/%s/mail/subscriptions\n' "$vmail_root" "$user_domain" "$user_local"
    }

    desired_subscriptions_file_for_user() {
      local user="$1"
      local user_hash

      user_hash="$(printf '%s' "$user" | sha256sum | awk '{print $1}')"
      printf '%s/%s\n' "$desired_subscriptions_dir" "$user_hash"
    }

    record_desired_subscription() {
      local user="$1"
      local mailbox="$2"
      local desired_file

      desired_file="$(desired_subscriptions_file_for_user "$user")"
      printf '%s\n' "$mailbox" >> "$desired_file"
    }

    project_managed_subscriptions() {
      local subscriptions_file="$1"
      local desired_file="$2"
      local managed_domain
      local managed_domains
      local managed_user
      local subscriptions_dir
      local tmp

      managed_domains="$(
        for managed_user in "''${all_users[@]}"; do
          managed_domain="''${managed_user#*@}"
          if [ -n "$managed_domain" ] && [ "$managed_domain" != "$managed_user" ]; then
            printf '%s\n' "$managed_domain"
          fi
        done | sort -u | tr '\n' ' '
      )"

      subscriptions_dir="$(dirname "$subscriptions_file")"
      if [ ! -d "$subscriptions_dir" ]; then
        echo "shared-mail-subscriptions: subscriptions directory is unavailable" >&2
        return 1
      fi

      tmp="$(mktemp "''${subscriptions_file}.tmp.XXXXXX")"
      {
        if [ -f "$subscriptions_file" ]; then
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
          ' "$subscriptions_file"
        fi

        if [ -f "$desired_file" ]; then
          sort -u "$desired_file"
        fi
      } | awk '
        NF != 0 && !seen[$0]++ {
          print
        }
      ' > "$tmp"

      if [ -f "$subscriptions_file" ]; then
        chown --reference="$subscriptions_file" "$tmp"
        chmod --reference="$subscriptions_file" "$tmp"
      else
        chown --reference="$subscriptions_dir" "$tmp"
        chmod 0600 "$tmp"
      fi
      mv "$tmp" "$subscriptions_file"
    }

    project_all_managed_subscriptions() {
      local desired_file

      for user in "''${all_users[@]}"; do
        subscriptions_file="$(subscriptions_file_for_user "$user" || true)"
        [ -n "$subscriptions_file" ] || continue
        desired_file="$(desired_subscriptions_file_for_user "$user")"
        project_managed_subscriptions "$subscriptions_file" "$desired_file"
      done
    }

    configured_automatic_mailboxes() {
      if [ -n "''${MAIL_SHARED_AUTO_MAILBOXES:-}" ]; then
        words "$MAIL_SHARED_AUTO_MAILBOXES"
        return
      fi

      if [ -n "''${MAIL_SHARED_AUTO_MAILBOX:-}" ]; then
        words "$MAIL_SHARED_AUTO_MAILBOX"
        return
      fi

      printf '%s\n' INBOX
    }

    mailbox_uses_inbox_acl_defaults() {
      local mailbox="$1"

      [ "$shared_inherit_inbox_acl" = "1" ] || return 1
      case "$mailbox" in
        ""|INBOX)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    }

    private_mailbox_visible() {
      local mailbox="$1"
      local managed_domain
      local managed_user

      case "$mailbox" in
        "$shared_namespace_prefix"|"$shared_namespace_prefix"/*|shared|shared/*|users|users/*)
          return 1
          ;;
      esac

      for managed_user in "''${all_users[@]}"; do
        managed_domain="''${managed_user#*@}"
        [ -n "$managed_domain" ] || continue
        [ "$managed_domain" != "$managed_user" ] || continue

        case "$mailbox" in
          "$managed_domain"|"$managed_domain"/*)
            return 1
            ;;
        esac
      done

      return 0
    }

    visible_mailboxes_for_share() {
      local owner="$1"
      local mailbox="$2"

      if mailbox_uses_inbox_acl_defaults "$mailbox"; then
        while IFS= read -r owner_mailbox; do
          [ -n "$owner_mailbox" ] || continue
          private_mailbox_visible "$owner_mailbox" || continue
          printf '%s\n' "$owner_mailbox"
        done < <(doveadm mailbox list -u "$owner")
      else
        printf '%s\n' "$mailbox"
      fi
    }

    ensure_mailbox() {
      local user="$1"
      local mailbox="$2"

      if ! doveadm mailbox status -u "$user" uidvalidity "$mailbox" >/dev/null 2>&1; then
        doveadm mailbox create -u "$user" -s "$mailbox" >/dev/null 2>&1 || true
      fi

      # Some Dovecot mailbox drivers list subscribed special-use mailboxes before
      # the backing Maildir exists. Update materializes the mailbox through
      # Dovecot itself so shared namespace lookups can resolve it immediately.
      doveadm mailbox update -u "$user" "$mailbox" >/dev/null 2>&1 || true
      doveadm mailbox status -u "$user" messages "$mailbox" >/dev/null 2>&1 || true
    }

    sync_automatic_account_mailboxes() {
      rights="''${MAIL_SHARED_AUTO_RIGHTS:-lookup read write write-seen write-deleted insert post expunge create delete}"

      [ "''${#owner_users[@]}" -ne 0 ] || return 0
      [ "''${#client_users[@]}" -ne 0 ] || return 0

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

        for mailbox in $(configured_automatic_mailboxes); do
          [ -n "$mailbox" ] || continue

          ensure_mailbox "$owner" "$mailbox"

          while IFS= read -r visible_source_mailbox; do
            [ -n "$visible_source_mailbox" ] || continue
            ensure_mailbox "$owner" "$visible_source_mailbox"

            for cleanup_user in "''${all_users[@]}"; do
              [ "$cleanup_user" != "$owner" ] || continue
              same_mail_domain "$owner" "$cleanup_user" || continue

              doveadm acl delete -u "$owner" "$visible_source_mailbox" "user=$cleanup_user" >/dev/null 2>&1 || true
            done
          done < <(visible_mailboxes_for_share "$owner" "$mailbox")
          doveadm acl recalc -u "$owner" >/dev/null

          for user in "''${client_users[@]}"; do
            [ "$user" != "$owner" ] || continue
            same_mail_domain "$owner" "$user" || continue

            if ! doveadm user "$user" >/dev/null 2>&1; then
              echo "shared-mail-subscriptions: automatic ACL user is not a Dovecot user: $user" >&2
              continue
            fi

            doveadm acl add -u "$owner" "$mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
            doveadm acl recalc -u "$owner" >/dev/null
            add_sender_login "$owner" "$user" "$rights"

            while IFS= read -r visible_source_mailbox; do
              [ -n "$visible_source_mailbox" ] || continue
              ensure_mailbox "$owner" "$visible_source_mailbox"
              if [ "$visible_source_mailbox" != "$mailbox" ]; then
                doveadm acl add -u "$owner" "$visible_source_mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
                doveadm acl recalc -u "$owner" >/dev/null
              fi
              visible_mailbox="$(shared_mailbox_name "$owner" "$visible_source_mailbox")"

              if subscribe_user "$user" "$visible_mailbox"; then
                subscribed=$((subscribed + 1))
              else
                failed=$((failed + 1))
              fi
            done < <(visible_mailboxes_for_share "$owner" "$mailbox")
          done
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

        ensure_mailbox "$owner" "$mailbox"

        rights_args=()
        for right in $(words "$rights"); do
          [ -n "$right" ] || continue
          rights_args+=("$right")
        done

        for user_ref in $(words "$user_refs"); do
          [ -n "$user_ref" ] || continue
          user="$user_ref"
          same_mail_domain "$owner" "$user" || continue

          if ! doveadm user "$user" >/dev/null 2>&1; then
            echo "shared-mail-subscriptions: ACL user is not a Dovecot user: $user_ref" >&2
            continue
          fi

          doveadm acl add -u "$owner" "$mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
          doveadm acl recalc -u "$owner" >/dev/null
          add_sender_login "$owner" "$user" "$rights"

          while IFS= read -r visible_source_mailbox; do
            [ -n "$visible_source_mailbox" ] || continue
            ensure_mailbox "$owner" "$visible_source_mailbox"
            if [ "$visible_source_mailbox" != "$mailbox" ]; then
              doveadm acl add -u "$owner" "$visible_source_mailbox" "user=$user" "''${rights_args[@]}" >/dev/null
              doveadm acl recalc -u "$owner" >/dev/null
            fi
            visible_mailbox="$(shared_mailbox_name "$owner" "$visible_source_mailbox")"

            if subscribe_user "$user" "$visible_mailbox"; then
              subscribed=$((subscribed + 1))
            else
              failed=$((failed + 1))
            fi
          done < <(visible_mailboxes_for_share "$owner" "$mailbox")
        done
      done
    }

    subscribe_user() {
      local user="$1"
      local mailbox="$2"
      local attempt

      if ! doveadm user "$user" >/dev/null 2>&1; then
        return 0
      fi

      for attempt in 1 2 3; do
        if doveadm acl debug -u "$user" "$mailbox" >/dev/null 2>&1; then
          record_desired_subscription "$user" "$mailbox"
          return 0
        fi

        [ "$attempt" = 3 ] || sleep 1
      done

      echo "shared-mail-subscriptions: mailbox is not visible for ACL user: user=$user mailbox=$mailbox" >&2
      return 1
    }

    subscribed=0
    failed=0
    : > "$shared_sender_logins_raw"

    load_mailbox_users
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

    project_all_managed_subscriptions
    echo "shared-mail-subscriptions: synced $subscribed subscription(s)"
  '';
}
