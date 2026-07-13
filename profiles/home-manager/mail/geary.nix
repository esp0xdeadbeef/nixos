{ config
, lib
, outPath
, pkgs
, profiles
, ...
}:
let
  mailboxSetNames = profiles.mail.inventory.hostedMailboxSets;
  mailboxSets = profiles.mail.mailbox-sets {
    inherit mailboxSetNames;
    secretsRoot = outPath + "/secrets";
  };
  mailboxSetEnvPaths = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "geary-mailbox-set-env-paths";
    secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
  };
  mailAccountEnvPaths = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "geary-mail-account-env-paths";
    secretRefs = mailboxSets.mailAccountEnvSecretRefs;
  };
  syncAccounts = pkgs.writeShellApplication {
    name = "geary-mail-account-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.geary
      pkgs.gawk
      pkgs.libsecret
      pkgs.procps
      pkgs.python3
    ];
    text = ''
      set -euo pipefail

      mailbox_set_path_list=${lib.escapeShellArg mailboxSetEnvPaths.pathList}
      mail_account_path_list=${lib.escapeShellArg mailAccountEnvPaths.pathList}
      python=${lib.escapeShellArg "${pkgs.python3}/bin/python3"}
      secret_tool=${lib.escapeShellArg "${pkgs.libsecret}/bin/secret-tool"}
      config_base="''${XDG_CONFIG_HOME:-$HOME/.config}/geary"
      data_base="''${XDG_DATA_HOME:-$HOME/.local/share}/geary"
      manifest_file="$config_base/.nix-managed-accounts"

      install -d -m 0700 "$config_base" "$data_base"
      old_manifest="$(mktemp "$manifest_file.old.XXXXXX")"
      new_manifest="$(mktemp "$manifest_file.new.XXXXXX")"
      trap 'rm -f "$old_manifest" "$new_manifest"' EXIT

      if [ -f "$manifest_file" ]; then
        cp "$manifest_file" "$old_manifest"
      else
        : > "$old_manifest"
      fi

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
        "$python" - "$1" <<'PY'
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

        for field in LOCALPART PASSWORD ALIASES CLIENT SERVER DEFAULT LABEL DISPLAY_NAME FROM SOURCE OUTGOING ADDRESS USERNAME IMAP_HOST SMTP_HOST MAIL_HOST IMAP_PORT SMTP_PORT; do
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

      account_is_default() {
        local account_ref="$1"
        local address="$2"

        if [ -n "''${MAILBOX_DEFAULT_ACCOUNT:-}" ] && [ "$account_ref" = "''${MAILBOX_DEFAULT_ACCOUNT:-}" ]; then
          return 0
        fi

        if [ -n "''${MAILBOX_DEFAULT_ADDRESS:-}" ] && [ "$address" = "''${MAILBOX_DEFAULT_ADDRESS:-}" ]; then
          return 0
        fi

        if [ -n "''${MAILBOX_DOMAIN:-}" ]; then
          return 1
        fi

        if bool_true "$(account_var DEFAULT)"; then
          return 0
        fi

        return 1
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

      account_label_for() {
        local address="$1"
        local label

        label="$(account_var LABEL)"
        if [ -z "$label" ]; then
          printf '%s\n' "$address"
        elif [ "$label" = "$address" ]; then
          printf '%s\n' "$label"
        else
          case "$label" in
            *@*)
              printf '%s\n' "$address"
              ;;
            *)
              printf '%s <%s>\n' "$label" "$address"
              ;;
          esac
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

      write_config() {
        local account_id="$1"
        local ordinal="$2"
        local label="$3"
        local sender="$4"
        local source="$5"
        local outgoing="$6"
        local account_dir="$config_base/$account_id"
        local data_dir="$data_base/$account_id"
        local config_file="$account_dir/geary.ini"

        install -d -m 0700 "$account_dir" "$data_dir"

        "$python" - "$config_file" "$ordinal" "$label" "$sender" "$source" "$outgoing" <<'PY'
      import email.utils
      import pathlib
      import sys
      import urllib.parse

      config_file, ordinal, label, sender, source, outgoing = sys.argv[1:]

      def parse_service(uri, protocol):
          parsed = urllib.parse.urlsplit(uri)
          user = urllib.parse.unquote(parsed.username or "")
          host = parsed.hostname or ""
          port = parsed.port
          scheme = parsed.scheme.lower()

          if protocol == "IMAP":
              if port is None:
                  port = 993 if scheme == "imaps" else 143
              security = "transport" if scheme == "imaps" or port == 993 else "start-tls"
          else:
              if port is None:
                  port = 465 if scheme == "smtps" else 587
              security = "transport" if scheme == "smtps" or port == 465 else "start-tls"

          if not user:
              raise SystemExit(f"{protocol} URI is missing a username: {uri}")
          if not host:
              raise SystemExit(f"{protocol} URI is missing a host: {uri}")

          return user, host, str(port), security

      def keyfile_escape(value):
          return (
              value
              .replace("\\", "\\\\")
              .replace("\n", "\\n")
              .replace("\r", "\\r")
              .replace("\t", "\\t")
              .replace(";", "\\;")
          )

      imap_user, imap_host, imap_port, imap_security = parse_service(source, "IMAP")
      smtp_user, smtp_host, smtp_port, smtp_security = parse_service(outgoing, "SMTP")
      _sender_name, sender_address = email.utils.parseaddr(sender)
      if not sender_address:
          raise SystemExit(f"sender address is invalid: {sender}")

      outgoing_credentials = "use-incoming" if smtp_user == imap_user else "custom"
      pathlib.Path(config_file).write_text(
          "\n".join([
              "[Metadata]",
              "version=1",
              "status=enabled",
              "",
              "[Account]",
              f"label={keyfile_escape(label)}",
              "service_provider=other",
              f"ordinal={ordinal}",
              "prefetch_days=14",
              "save_drafts=true",
              "save_sent=true",
              "use_signature=false",
              "signature=",
              f"sender_mailboxes={keyfile_escape(sender)};",
              "",
              "[Folders]",
              "archive_folder=Archive;",
              "drafts_folder=Drafts;",
              "sent_folder=Sent;",
              "junk_folder=Junk;",
              "trash_folder=Trash;",
              "",
              "[Incoming]",
              f"login={keyfile_escape(imap_user)}",
              "remember_password=true",
              f"host={keyfile_escape(imap_host)}",
              f"port={imap_port}",
              f"transport_security={imap_security}",
              "credentials=custom",
              "",
              "[Outgoing]",
              f"login={keyfile_escape(smtp_user)}",
              "remember_password=true",
              f"host={keyfile_escape(smtp_host)}",
              f"port={smtp_port}",
              f"transport_security={smtp_security}",
              f"credentials={outgoing_credentials}",
              "",
          ]),
          encoding="utf-8",
      )
      print("\t".join([imap_user, imap_host, smtp_user, smtp_host, outgoing_credentials]))
      PY
      }

      store_passwords() {
        local password="$1"
        local imap_user="$2"
        local imap_host="$3"
        local smtp_user="$4"
        local smtp_host="$5"
        local outgoing_credentials="$6"

        printf '%s' "$password" | "$secret_tool" store \
          --label="Geary IMAP password" \
          xdg:schema org.gnome.Geary \
          proto IMAP \
          host "$imap_host" \
          login "$imap_user"

        if [ "$outgoing_credentials" = "custom" ]; then
          printf '%s' "$password" | "$secret_tool" store \
            --label="Geary SMTP password" \
            xdg:schema org.gnome.Geary \
            proto SMTP \
            host "$smtp_host" \
            login "$smtp_user"
        fi
      }

      write_geary_account() {
        local account_ref="$1"
        local address="$2"
        local label
        local sender
        local source
        local outgoing
        local password
        local parsed
        local imap_user
        local parsed_imap_host
        local smtp_user
        local parsed_smtp_host
        local outgoing_credentials
        local geary_account_id
        local is_default

        if ! bool_true "$(account_var CLIENT)"; then
          return 0
        fi

        is_default=0
        if account_is_default "$account_ref" "$address"; then
          is_default=1
        fi

        case "$write_account_pass" in
          default)
            [ "$is_default" -eq 1 ] || return 0
            ;;
          rest)
            [ "$is_default" -eq 0 ] || return 0
            ;;
          *)
            echo "invalid Geary account sync pass: $write_account_pass" >&2
            exit 1
            ;;
        esac

        label="$(account_label_for "$address")"
        sender="$(sender_for "$address")"
        source="$(resolve_source "$address")" || {
          echo "mail account is missing SOURCE or IMAP host: $account_ref" >&2
          exit 1
        }
        outgoing="$(resolve_outgoing "$address")" || {
          echo "mail account is missing OUTGOING or SMTP host: $account_ref" >&2
          exit 1
        }
        password="$(account_var PASSWORD)"
        if [ -z "$password" ]; then
          echo "mail account is missing PASSWORD: $account_ref" >&2
          exit 1
        fi

        geary_account_id="account_$(printf '%02d' "$((ordinal + 1))")"
        parsed="$(write_config "$geary_account_id" "$ordinal" "$label" "$sender" "$source" "$outgoing")"
        generated_account_ids+=("$geary_account_id")
        IFS=$'\t' read -r imap_user parsed_imap_host smtp_user parsed_smtp_host outgoing_credentials <<< "$parsed"
        store_passwords "$password" "$imap_user" "$parsed_imap_host" "$smtp_user" "$parsed_smtp_host" "$outgoing_credentials"
        ordinal=$((ordinal + 1))
      }

      sync_hosted_accounts() {
        while IFS= read -r entry; do
          [ -n "$entry" ] || continue
          mailbox_set_env_file="''${entry#*=}"

          if [ ! -r "$mailbox_set_env_file" ]; then
            echo "mailbox set env is missing: $mailbox_set_env_file" >&2
            exit 1
          fi

          unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS MAILBOX_DEFAULT_ACCOUNT MAILBOX_DEFAULT_ADDRESS MAILBOX_MAIL_HOST MAILBOX_IMAP_HOST MAILBOX_SMTP_HOST MAILBOX_IMAP_PORT MAILBOX_SMTP_PORT
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
            write_geary_account "$account_ref" "$address"
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

          unset MAILBOX_DOMAIN MAILBOX_ACCOUNTS MAILBOX_DEFAULT_ACCOUNT MAILBOX_DEFAULT_ADDRESS MAILBOX_MAIL_HOST MAILBOX_IMAP_HOST MAILBOX_SMTP_HOST MAILBOX_IMAP_PORT MAILBOX_SMTP_PORT
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

          write_geary_account "$account_ref" "$address"
          unset_account_vars
        done < "$mail_account_path_list"
      }

      account_id_is_generated() {
        local needle="$1"
        local account_id

        for account_id in "''${generated_account_ids[@]}"; do
          if [ "$account_id" = "$needle" ]; then
            return 0
          fi
        done

        return 1
      }

      remove_stale_managed_accounts() {
        local old_account_id
        local _old_checksum

        while IFS=$'\t' read -r old_account_id _old_checksum; do
          [ -n "$old_account_id" ] || continue
          if ! account_id_is_generated "$old_account_id"; then
            rm -rf -- "''${config_base:?}/$old_account_id" "''${data_base:?}/$old_account_id"
          fi
        done < "$old_manifest"
      }

      write_managed_manifest() {
        local account_id
        local config_file
        local checksum

        : > "$new_manifest"
        for account_id in "''${generated_account_ids[@]}"; do
          config_file="$config_base/$account_id/geary.ini"
          [ -f "$config_file" ] || continue
          checksum="$(sha256sum "$config_file" | awk '{ print $1 }')"
          printf '%s\t%s\n' "$account_id" "$checksum" >> "$new_manifest"
        done
      }

      quit_geary_if_accounts_changed() {
        if cmp -s "$old_manifest" "$new_manifest"; then
          return 0
        fi

        if pgrep -u "$(id -u)" -f '/bin/geary( |$)' >/dev/null 2>&1; then
          geary -q >/dev/null 2>&1 || true
        fi
      }

      generated_account_ids=()
      ordinal=0
      write_account_pass=default
      sync_hosted_accounts
      sync_external_accounts
      write_account_pass=rest
      sync_hosted_accounts
      sync_external_accounts
      remove_stale_managed_accounts
      write_managed_manifest
      quit_geary_if_accounts_changed
      install -m 0600 "$new_manifest" "$manifest_file"
    '';
  };
in
{
  home.packages = with pkgs; [
    geary
    libsecret
  ];

  dconf = {
    enable = true;
    settings."org/gnome/Geary".run-in-background = true;
  };

  sops.secrets = mailboxSets.mkSopsSecrets { };

  systemd.user.services.geary-account-sync = {
    Unit = {
      Description = "Sync Geary accounts from SOPS mail account profiles";
      Wants = [ "sops-nix.service" ];
      After = [
        "sops-nix.service"
        "graphical-session.target"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe syncAccounts;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "message/rfc822" = [ "org.gnome.Geary.desktop" ];
      "x-scheme-handler/mailto" = [ "org.gnome.Geary.desktop" ];
    };
  };
}
