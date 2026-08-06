{ dovecotRuntimeDir
, hostName
, lib
, mailAccountEnvPathList
, mailEnvPath
, mailboxSetEnvPathList
, mailTlsFullchainPath
, mailTlsKeyPath
, networkAddressEnvPath
, pkgs
, postfixRuntimeDir
, sharedSenderLoginMap
}:

pkgs.writeShellApplication {
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
    vmailbox="$postfix_dir/vmailbox"
    vaccounts_raw="$postfix_dir/vaccounts.raw"
    vaccounts="$postfix_dir/vaccounts"
    shared_vaccounts=${lib.escapeShellArg sharedSenderLoginMap}
    local_sender_reject="$postfix_dir/local_sender_reject"
    passwd_file="$dovecot_dir/passwd"

    : > "$vdomains"
    : > "$vdomains_raw"
    : > "$valias_domains"
    : > "$valias_domains_raw"
    : > "$valias"
    : > "$vmailbox"
    : > "$vaccounts_raw"
    : > "$vaccounts"
    : > "$shared_vaccounts"
    : > "$local_sender_reject"
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

      catchall_target="''${MAILBOX_CATCHALL:-}"
      mailbox_aliases="''${MAILBOX_ALIASES:-}"
      catchall_password_hash=""
      catchall_owner_home=""

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
        owner_domain="''${address#*@}"
        owner_local="''${address%@*}"
        owner_home="/var/vmail/$owner_domain/$owner_local"

        if [ -z "$password" ]; then
          echo "mail account is missing PASSWORD: $account_ref" >&2
          exit 1
        fi

        password_hash="$(doveadm pw -s BLF-CRYPT -p "$password")"
        unset password

        printf '%s %s\n' "$address" "$address" >> "$vmailbox"
        printf '%s %s\n' "$address" "$address" >> "$vaccounts_raw"
        printf '%s:%s::::::\n' "$address" "$password_hash" >> "$passwd_file"

        for alias in $(words "$aliases"); do
          [ -n "$alias" ] || continue
          alias_address="$(expand_address "$domain" "$alias")"
          write_address_domain "$alias_address" "$valias_domains_raw"
          printf '%s %s\n' "$alias_address" "$address" >> "$valias"
          printf '%s %s\n' "$alias_address" "$address" >> "$vaccounts_raw"
          printf '%s:%s::::%s::mail=maildir:%s/mail\n' "$alias_address" "$password_hash" "$owner_home" "$owner_home" >> "$passwd_file"
        done

        if [ -n "$catchall_target" ]; then
          catchall_check="$(expand_address "$first_domain" "$catchall_target")"
          if [ "$address" = "$catchall_check" ]; then
            catchall_password_hash="$password_hash"
            catchall_owner_home="$owner_home"
          fi
        fi

        unset_account_vars
      done

      if [ -n "$mailbox_aliases" ]; then
        for alias_spec in $mailbox_aliases; do
          [ -n "$alias_spec" ] || continue

          alias_localpart="''${alias_spec%%=*}"
          targets="''${alias_spec#*=}"

          # Fall back to catchall if no explicit targets
          if [ -z "$targets" ] || [ "$targets" = "$alias_spec" ]; then
            if [ -z "$catchall_password_hash" ]; then
              continue
            fi
            catchall_addr="$(expand_address "$first_domain" "$catchall_target")"
            targets="$catchall_addr"
            # Collect per-target details for the catchall
            target_passwd="$catchall_password_hash"
            target_home="$catchall_owner_home"

            alias_address="$(expand_address "$domain" "$alias_localpart")"
            write_address_domain "$alias_address" "$valias_domains_raw"
            printf '%s %s\n' "$alias_address" "$targets" >> "$valias"
            printf '%s %s\n' "$alias_address" "$targets" >> "$vaccounts_raw"
            printf '%s:%s::::%s::mail=maildir:%s/mail\n' \
              "$alias_address" "$target_passwd" "$target_home" "$target_home" >> "$passwd_file"
          else
            # Comma-separated targets → Postfix recipient list
            alias_address="$(expand_address "$domain" "$alias_localpart")"
            write_address_domain "$alias_address" "$valias_domains_raw"

            expanded=""
            remaining="''${targets},"
            while [ -n "$remaining" ] && [ "''${remaining%,}" != "" ]; do
              target="''${remaining%%,*}"
              remaining="''${remaining#*,}"
              [ -n "$target" ] || continue
              target_addr="$(expand_address "$first_domain" "$target")"
              if [ -z "$expanded" ]; then
                expanded="$target_addr"
              else
                expanded="$expanded,$target_addr"
              fi
            done

            if [ -n "$expanded" ]; then
              printf '%s %s\n' "$alias_address" "$expanded" >> "$valias"
            fi
          fi
        done
      fi

      if [ -n "$catchall_target" ]; then
        catchall_address="$(expand_address "$first_domain" "$catchall_target")"
        printf '@%s %s\n' "$domain" "$catchall_address" >> "$valias"
      fi
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
      NF && !seen[$1]++ {
        print $1, "REJECT Sender domain is locally hosted; submit via authenticated SMTP on port 587"
      }
    ' "$vdomains_raw" > "$local_sender_reject"

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
    chown root:postfix "$vdomains" "$valias_domains" "$valias" "$vmailbox" "$vaccounts" "$shared_vaccounts" "$local_sender_reject"
    chmod 0640 "$vdomains" "$valias_domains" "$valias" "$vmailbox" "$vaccounts" "$shared_vaccounts" "$local_sender_reject"
    chown root:dovecot2 "$passwd_file"
    chmod 0440 "$passwd_file"

    postmap "$vdomains"
    postmap "$valias_domains"
    postmap "$valias"
    postmap "$vmailbox"
    postmap "$vaccounts"
    postmap "$shared_vaccounts"
    postmap "$local_sender_reject"
    chown root:postfix "$vdomains.db" "$valias_domains.db" "$valias.db" "$vmailbox.db" "$vaccounts.db" "$shared_vaccounts.db" "$local_sender_reject.db"
    chmod 0640 "$vdomains.db" "$valias_domains.db" "$valias.db" "$vmailbox.db" "$vaccounts.db" "$shared_vaccounts.db" "$local_sender_reject.db"

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
      "virtual_mailbox_maps = hash:$vmailbox" \
      "virtual_alias_maps = hash:$valias" \
      "smtpd_sender_login_maps = hash:$vaccounts hash:$shared_vaccounts" \
      "smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, check_sender_access hash:$local_sender_reject" \
      "smtpd_tls_chain_files = $tls_key $tls_fullchain"

    postfix -c /var/lib/postfix/conf check
  '';
}
