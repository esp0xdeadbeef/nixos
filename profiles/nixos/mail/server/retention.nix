{ hostName
, lib
, mailAccountEnvPathList
, mailboxSetEnvPathList
, pkgs
, retentionMaxDays
}:

pkgs.writeShellApplication {
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
}
