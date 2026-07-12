{ config
, lib
, outPath
, pkgs
, profiles
, ...
}:
let
  mailboxSets = profiles.mail.mailbox-sets {
    secretsRoot = outPath + "/secrets";
  };
  mailboxSetEnvPaths = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "aerc-mailbox-set-env-paths";
    secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
  };
  mailAccountEnvPaths = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "aerc-mail-account-env-paths";
    secretRefs = mailboxSets.mailAccountEnvSecretRefs;
  };
  defaultBinds = builtins.readFile ./aerc-binds.conf;
  passwordHelper = pkgs.writeShellApplication {
    name = "mail-account-password";
    text = ''
      set -euo pipefail

      if [ "$#" -ne 1 ]; then
        echo "usage: mail-account-password <account-env-file>" >&2
        exit 2
      fi

      account_env_file="$1"

      if [ ! -r "$account_env_file" ]; then
        echo "mail account env is missing: $account_env_file" >&2
        exit 1
      fi

      set -a
      # shellcheck disable=SC1090
      . "$account_env_file"
      set +a

      password="''${MAIL_ACCOUNT_PASSWORD:-}"
      if [ -z "$password" ]; then
        echo "mail account is missing PASSWORD: $account_env_file" >&2
        exit 1
      fi

      printf '%s\n' "$password"
    '';
  };
  syncAccounts = pkgs.writeShellApplication {
    name = "aerc-mail-account-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.python3
    ];
    text = ''
      set -euo pipefail

      mailbox_set_path_list=${lib.escapeShellArg mailboxSetEnvPaths.pathList}
      mail_account_path_list=${lib.escapeShellArg mailAccountEnvPaths.pathList}
      password_helper=${lib.escapeShellArg (lib.getExe passwordHelper)}
      accounts_file="''${XDG_CONFIG_HOME:-$HOME/.config}/aerc/accounts.conf"

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

      bool_false() {
        case "''${1:-}" in
          0|false|no|off) return 0 ;;
          *) return 1 ;;
        esac
      }

      urlencode() {
        python3 - "$1" <<'PY'
      import sys
      import urllib.parse

      print(urllib.parse.quote(sys.argv[1], safe=""))
      PY
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
        ' "$mail_account_path_list"
      }

      unset_account_vars() {
        local field

        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER LABEL DISPLAY_NAME FROM SOURCE OUTGOING ADDRESS USERNAME IMAP_HOST SMTP_HOST MAIL_HOST IMAP_PORT SMTP_PORT; do
          unset "MAIL_ACCOUNT_$field"
        done
      }

      load_account_env_file() {
        local account_env_file="$1"

        if [ ! -r "$account_env_file" ]; then
          echo "mail account env is missing: $account_env_file" >&2
          exit 1
        fi

        unset_account_vars
        set -a
        # shellcheck disable=SC1090
        . "$account_env_file"
        set +a
      }

      load_account_ref() {
        local account_ref="$1"
        local account_env_file

        account_env_file="$(account_env_path "$account_ref")" || {
          echo "mail account secret is not declared for client: $account_ref" >&2
          exit 1
        }

        load_account_env_file "$account_env_file"
        printf '%s\n' "$account_env_file"
      }

      account_var() {
        local field="$1"
        printenv "MAIL_ACCOUNT_$field" || true
      }

      hosted_address() {
        local domain="$1"
        local account_ref="$2"
        local localpart

        localpart="$(account_var LOCALPART)"
        if [ -z "$localpart" ]; then
          echo "mail account is missing LOCALPART: $account_ref" >&2
          exit 1
        fi

        printf '%s@%s\n' "$localpart" "$domain"
      }

      sender_for() {
        local address="$1"
        local sender
        local display_name

        sender="$(account_var FROM)"
        display_name="$(account_var DISPLAY_NAME)"

        if [ -n "$sender" ]; then
          printf '%s\n' "$sender"
        elif [ -n "$display_name" ]; then
          printf '%s <%s>\n' "$display_name" "$address"
        else
          printf '%s\n' "$address"
        fi
      }

      service_uri() {
        local scheme="$1"
        local host="$2"
        local port="$3"
        local address="$4"
        local encoded_address

        if [ -z "$host" ]; then
          return 1
        fi

        encoded_address="$(urlencode "$address")"

        if [ -n "$port" ]; then
          printf '%s://%s@%s:%s\n' "$scheme" "$encoded_address" "$host" "$port"
        else
          printf '%s://%s@%s\n' "$scheme" "$encoded_address" "$host"
        fi
      }

      resolve_source() {
        local address="$1"
        local explicit
        local host
        local port

        explicit="$(account_var SOURCE)"
        [ -z "$explicit" ] || {
          printf '%s\n' "$explicit"
          return 0
        }

        host="''${MAILBOX_IMAP_HOST:-}"
        [ -n "$host" ] || host="$(account_var IMAP_HOST)"
        [ -n "$host" ] || host="''${MAILBOX_MAIL_HOST:-}"
        [ -n "$host" ] || host="$(account_var MAIL_HOST)"
        port="''${MAILBOX_IMAP_PORT:-}"
        [ -n "$port" ] || port="$(account_var IMAP_PORT)"

        service_uri imaps "$host" "$port" "$address" || return 1
      }

      resolve_outgoing() {
        local address="$1"
        local explicit
        local host
        local port

        explicit="$(account_var OUTGOING)"
        [ -z "$explicit" ] || {
          printf '%s\n' "$explicit"
          return 0
        }

        host="''${MAILBOX_SMTP_HOST:-}"
        [ -n "$host" ] || host="$(account_var SMTP_HOST)"
        [ -n "$host" ] || host="''${MAILBOX_MAIL_HOST:-}"
        [ -n "$host" ] || host="$(account_var MAIL_HOST)"
        port="''${MAILBOX_SMTP_PORT:-}"
        [ -n "$port" ] || port="$(account_var SMTP_PORT)"

        service_uri smtps "$host" "$port" "$address" || return 1
      }

      write_account() {
        local account_env_file="$1"
        local account_ref="$2"
        local address="$3"
        local label
        local sender
        local source
        local outgoing

        if ! bool_true "$(account_var CLIENT)"; then
          return 0
        fi

        label="$(account_var LABEL)"
        if [ -z "$label" ]; then
          label="$address"
        elif [ "$label" != "$address" ]; then
          label="$label <$address>"
        fi
        sender="$(sender_for "$address")"

        source="$(resolve_source "$address")" || {
          echo "mail account is missing SOURCE or IMAP host: $account_ref" >&2
          exit 1
        }
        outgoing="$(resolve_outgoing "$address")" || {
          echo "mail account is missing OUTGOING or SMTP host: $account_ref" >&2
          exit 1
        }

        if [ -z "$(account_var PASSWORD)" ]; then
          echo "mail account is missing PASSWORD: $account_ref" >&2
          exit 1
        fi

        {
          printf '[%s]\n' "$label"
          printf 'from = %s\n' "$sender"
          printf 'source = %s\n' "$source"
          printf 'source-cred-cmd = %s %s\n' "$password_helper" "$account_env_file"
          printf 'outgoing = %s\n' "$outgoing"
          printf 'outgoing-cred-cmd = %s %s\n' "$password_helper" "$account_env_file"
          printf 'default = INBOX\n'
          printf 'copy-to = Sent\n'
          printf 'postpone = Drafts\n'
          printf '\n'
        } >> "$tmp"
      }

      sync_hosted_accounts() {
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          mailbox_set_env_file="''${entry#*=}"

          if [ ! -r "$mailbox_set_env_file" ]; then
            echo "mailbox set env is missing: $mailbox_set_env_file" >&2
            exit 1
          fi

          unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS MAILBOX_MAIL_HOST MAILBOX_IMAP_HOST MAILBOX_SMTP_HOST MAILBOX_IMAP_PORT MAILBOX_SMTP_PORT
          set -a
          # shellcheck disable=SC1090
          . "$mailbox_set_env_file"
          set +a

          domain="''${MAILBOX_DOMAIN:-}"
          account_refs="''${MAILBOX_ACCOUNTS:-}"

          if [ -z "$domain" ]; then
            echo "mailbox set is missing MAILBOX_DOMAIN: $mailbox_set_env_file" >&2
            exit 1
          fi

          for account_ref in $(words "$account_refs"); do
            [ -n "$account_ref" ] || continue
            account_env_file="$(account_env_path "$account_ref")" || {
              echo "mail account secret is not declared for client: $account_ref" >&2
              exit 1
            }
            load_account_env_file "$account_env_file"
            if bool_false "''${MAIL_ACCOUNT_SERVER:-true}"; then
              unset_account_vars
              continue
            fi

            address="$(hosted_address "$domain" "$account_ref")"
            write_account "$account_env_file" "$account_ref" "$address"
            unset_account_vars
          done
        done < "$mailbox_set_path_list"
      }

      sync_external_accounts() {
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          secret_name="''${entry%%=*}"
          account_env_file="''${entry#*=}"
          account_ref="''${secret_name#mail/accounts/}"
          account_ref="''${account_ref%/env}"

          load_account_env_file "$account_env_file"

          if ! bool_true "$(account_var CLIENT)" || ! bool_false "''${MAIL_ACCOUNT_SERVER:-true}"; then
            unset_account_vars
            continue
          fi

          address="$(account_var ADDRESS)"
          [ -n "$address" ] || address="$(account_var USERNAME)"
          if [ -z "$address" ]; then
            echo "external mail account is missing ADDRESS or USERNAME: $account_ref" >&2
            exit 1
          fi

          write_account "$account_env_file" "$account_ref" "$address"
          unset_account_vars
        done < "$mail_account_path_list"
      }

      install -d -m 0700 "$(dirname "$accounts_file")"
      tmp="$(mktemp "$accounts_file.tmp.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      {
        printf '# Generated from SOPS mail account profiles.\n'
        printf '# The source/outgoing URIs intentionally exclude passwords.\n\n'
      } > "$tmp"

      sync_hosted_accounts
      sync_external_accounts

      install -m 0600 "$tmp" "$accounts_file"
    '';
  };
in
{
  programs.aerc = {
    enable = true;
    extraBinds = defaultBinds;
  };

  sops.secrets = mailboxSets.mkSopsSecrets { };

  systemd.user.services.aerc-account-sync = {
    Unit = {
      Description = "Sync aerc accounts from SOPS mail account profiles";
      Wants = [ "sops-nix.service" ];
      After = [ "sops-nix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe syncAccounts;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
