{ config, lib, outPath, pkgs, ... }:
let
  mailAccounts = import ../../mail/accounts.nix {
    secretsRoot = "${outPath}/secrets";
  };
  accountNames = mailAccounts.clientAccountNames;
  accountSecretRefs = lib.flatten (
    map
      (
        account:
        map (field: mailAccounts.secretRef account field) mailAccounts.clientFields
      )
      accountNames
  );

  secretPath = name: config.sops.secrets.${name}.path;
  mkSecret = secret: {
    inherit (secret) name;
    value.sopsFile = secret.sopsFile;
  };
  accountId = index: "account_${if index + 1 < 10 then "0" else ""}${toString (index + 1)}";
  mkSyncAccount = index: account: ''
    sync_account \
      ${lib.escapeShellArg (accountId index)} \
      ${lib.escapeShellArg (toString index)} \
      ${lib.escapeShellArg (secretPath (mailAccounts.secretName account "label"))} \
      ${lib.escapeShellArg (secretPath (mailAccounts.secretName account "from"))} \
      ${lib.escapeShellArg (secretPath (mailAccounts.secretName account "source"))} \
      ${lib.escapeShellArg (secretPath (mailAccounts.secretName account "outgoing"))} \
      ${lib.escapeShellArg (secretPath (mailAccounts.secretName account "password"))}
  '';
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

  sops.secrets = builtins.listToAttrs (map mkSecret accountSecretRefs);

  sops.templates.gearyAccountSync = {
    mode = "0700";
    content = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      python=${lib.escapeShellArg "${pkgs.python3}/bin/python3"}
      secret_tool=${lib.escapeShellArg "${pkgs.libsecret}/bin/secret-tool"}
      config_base="''${XDG_CONFIG_HOME:-$HOME/.config}/geary"
      data_base="''${XDG_DATA_HOME:-$HOME/.local/share}/geary"

      install -d -m 0700 "$config_base" "$data_base"

      read_secret_file() {
        tr -d '\r\n' < "$1"
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
      sender_name, sender_address = email.utils.parseaddr(sender)
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
        local password_file="$1"
        local imap_user="$2"
        local imap_host="$3"
        local smtp_user="$4"
        local smtp_host="$5"
        local outgoing_credentials="$6"
        local password

        password="$(tr -d '\r\n' < "$password_file")"

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

        unset password
      }

      sync_account() {
        local account_id="$1"
        local ordinal="$2"
        local label_file="$3"
        local sender_file="$4"
        local source_file="$5"
        local outgoing_file="$6"
        local password_file="$7"
        local label
        local sender
        local source
        local outgoing
        local parsed
        local imap_user
        local imap_host
        local smtp_user
        local smtp_host
        local outgoing_credentials

        label="$(read_secret_file "$label_file")"
        sender="$(read_secret_file "$sender_file")"
        source="$(read_secret_file "$source_file")"
        outgoing="$(read_secret_file "$outgoing_file")"

        parsed="$(write_config "$account_id" "$ordinal" "$label" "$sender" "$source" "$outgoing")"
        IFS=$'\t' read -r imap_user imap_host smtp_user smtp_host outgoing_credentials <<< "$parsed"
        store_passwords "$password_file" "$imap_user" "$imap_host" "$smtp_user" "$smtp_host" "$outgoing_credentials"
      }

      ${lib.concatStringsSep "\n" (lib.imap0 mkSyncAccount accountNames)}
    '';
  };

  systemd.user.services.geary-account-sync = {
    Unit = {
      Description = "Sync Geary accounts from SOPS";
      Wants = [ "sops-nix.service" ];
      After = [
        "sops-nix.service"
        "graphical-session.target"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = config.sops.templates.gearyAccountSync.path;
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
