{ config
, lib
, mailboxSets ? null
, pkgs
, ...
}:
let
  cfg = config.profiles.mail.classifier;
  serviceName = "mail-classifier";
  user = serviceName;
  group = serviceName;

  classifier = pkgs.writeTextFile {
    name = serviceName;
    destination = "/bin/${serviceName}";
    executable = true;
    text = ''
      #!${lib.getExe pkgs.python3}
      ${builtins.readFile ./classifier.py}
    '';
  };

  classifierValidation = pkgs.runCommandLocal "${serviceName}-validation"
    {
      nativeBuildInputs = [ pkgs.python3 ];
      source = ./classifier.py;
    }
    ''
      ${lib.getExe classifier} --self-test >/dev/null

      python3 - "$source" <<'PY'
      import ast
      import pathlib
      import sys

      source = pathlib.Path(sys.argv[1])
      tree = ast.parse(source.read_text(), filename=str(source))

      forbidden_imports = {"smtplib"}
      forbidden_methods = {
          "copy",
          "delete",
          "expunge",
          "send_message",
          "sendmail",
          "store",
      }
      allowed_uid_commands = {"FETCH", "MOVE", "SEARCH"}
      seen_uid_commands = set()

      for node in ast.walk(tree):
          if isinstance(node, ast.Import):
              imported = {name.name.split(".", 1)[0] for name in node.names}
              if imported & forbidden_imports:
                  raise SystemExit(
                      f"forbidden mail transport import: "
                      f"{sorted(imported & forbidden_imports)}"
                  )
          if isinstance(node, ast.ImportFrom):
              imported = (node.module or "").split(".", 1)[0]
              if imported in forbidden_imports:
                  raise SystemExit(f"forbidden mail transport import: {imported}")

          if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
              continue

          method = node.func.attr.lower()
          if method in forbidden_methods:
              raise SystemExit(f"forbidden mutating IMAP method: {method}")

          if method != "uid":
              continue
          if not node.args or not isinstance(node.args[0], ast.Constant):
              raise SystemExit("every IMAP UID command must be a static string")

          command = node.args[0].value
          if not isinstance(command, str) or command not in allowed_uid_commands:
              raise SystemExit(f"forbidden IMAP UID command: {command!r}")
          seen_uid_commands.add(command)

      if seen_uid_commands != allowed_uid_commands:
          raise SystemExit(
              f"expected exactly {sorted(allowed_uid_commands)}, "
              f"found {sorted(seen_uid_commands)}"
          )

      source_text = source.read_text()
      if '"(BODY.PEEK[])"' not in source_text:
          raise SystemExit("message fetches must retain BODY.PEEK[] semantics")
      PY

      touch "$out"
    '';

  configFile = pkgs.writeText "${serviceName}.json" (builtins.toJSON {
    inherit (cfg)
      destinations
      dryRun
      feedbackMailbox
      imapTimeoutSeconds
      lowConfidenceLabel
      maximumBodyCharacters
      maxMessagesPerMailbox
      minimumConfidence
      replyMailbox
      sharedNamespacePrefix
      ;
    ollama = {
      inherit (cfg.ollama) baseUrl model timeoutSeconds;
    };
  });

  mailboxSetEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${serviceName}-mailbox-set-env-paths";
    secretRefs = mailboxSets.mailboxSetEnvSecretRefs;
  };
  mailAccountEnvPathsConfig = mailboxSets.mkEnvPaths {
    inherit config lib pkgs;
    name = "${serviceName}-mail-account-env-paths";
    secretRefs = mailboxSets.mailAccountEnvSecretRefs;
  };
  mailboxSetEnvPathList = mailboxSetEnvPathsConfig.pathList;
  mailAccountEnvPathList = mailAccountEnvPathsConfig.pathList;
  secretPaths = mailboxSetEnvPathsConfig.paths ++ mailAccountEnvPathsConfig.paths;

  classifierSecrets = builtins.listToAttrs (
    map
      (secret: {
        inherit (secret) name;
        value = {
          inherit (secret) key sopsFile;
          inherit group;
          owner = user;
          mode = "0400";
          restartUnits = [ "${serviceName}.service" ];
        };
      })
      mailboxSets.envSecretRefs
  );

  allowList = lib.concatStringsSep " " cfg.mailboxSetAllowList;

  requireReadableSecrets = ''
    for secret_path in ${lib.concatMapStringsSep " " lib.escapeShellArg secretPaths}; do
      if [ ! -r "$secret_path" ]; then
        echo "mail-classifier: protected runtime profile is unavailable" >&2
        exit 1
      fi
    done
  '';

  runner = pkgs.writeShellApplication {
    name = "${serviceName}-run";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      set -euo pipefail
      set +x

      mailbox_set_env_path_list=${lib.escapeShellArg mailboxSetEnvPathList}
      mail_account_env_path_list=${lib.escapeShellArg mailAccountEnvPathList}
      mailbox_set_allow_list=${lib.escapeShellArg allowList}
      failures=0
      processed_accounts=0

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

      allow_mailbox_set() {
        local mailbox_set="$1"
        local allowed

        [ -z "$mailbox_set_allow_list" ] && return 0
        for allowed in $mailbox_set_allow_list; do
          [ "$mailbox_set" != "$allowed" ] || return 0
        done
        return 1
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

      unset_prefixed_vars() {
        local prefix="$1"
        local variable

        while IFS='=' read -r variable _; do
          case "$variable" in
            "$prefix"*)
              unset "$variable"
              ;;
          esac
        done < <(env)
      }

      unset_account_vars() {
        unset_prefixed_vars MAIL_ACCOUNT_
      }

      unset_mailbox_vars() {
        unset_prefixed_vars MAILBOX_
      }

      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        secret_name="''${entry%%=*}"
        mailbox_set_path="''${entry#*=}"
        mailbox_set="$(printf '%s\n' "$secret_name" | awk -F/ '{print $(NF - 1)}')"

        allow_mailbox_set "$mailbox_set" || continue
        [ -r "$mailbox_set_path" ] || continue

        unset_mailbox_vars
        set -a
        # shellcheck disable=SC1090
        . "$mailbox_set_path"
        set +a

        domain="''${MAILBOX_DOMAIN:-}"
        account_refs="''${MAILBOX_ACCOUNTS:-}"
        mailbox_imap_host="''${MAILBOX_IMAP_HOST:-''${MAILBOX_MAIL_HOST:-}}"
        mailbox_imap_port="''${MAILBOX_IMAP_PORT:-993}"
        unset_mailbox_vars
        [ -n "$domain" ] || continue

        for account_ref in $(words "$account_refs"); do
          [ -n "$account_ref" ] || continue
          account_path="$(account_env_path "$account_ref")" || continue
          [ -r "$account_path" ] || continue

          unset_account_vars
          set -a
          # shellcheck disable=SC1090
          . "$account_path"
          set +a

          if ! bool_true "''${MAIL_ACCOUNT_SERVER:-true}" \
            || ! bool_true "''${MAIL_ACCOUNT_CLIENT:-false}"; then
            unset_account_vars
            continue
          fi

          localpart="''${MAIL_ACCOUNT_LOCALPART:-}"
          password="''${MAIL_ACCOUNT_PASSWORD:-}"
          imap_host="''${MAIL_ACCOUNT_IMAP_HOST:-$mailbox_imap_host}"
          imap_port="''${MAIL_ACCOUNT_IMAP_PORT:-$mailbox_imap_port}"
          username="''${MAIL_ACCOUNT_USERNAME:-$localpart@$domain}"

          if [ -z "$localpart" ] || [ -z "$password" ] || [ -z "$imap_host" ]; then
            echo "mail-classifier: incomplete protected account profile: $mailbox_set/$account_ref" >&2
            failures=$((failures + 1))
            unset_account_vars
            continue
          fi

          export MAIL_CLASSIFIER_ACCOUNT_ID="$mailbox_set/$account_ref"
          export MAIL_CLASSIFIER_IMAP_HOST="$imap_host"
          export MAIL_CLASSIFIER_IMAP_PORT="$imap_port"
          export MAIL_CLASSIFIER_IMAP_USERNAME="$username"
          export MAIL_CLASSIFIER_IMAP_PASSWORD="$password"
          unset_account_vars

          if ${lib.getExe classifier} --config ${lib.escapeShellArg configFile}; then
            processed_accounts=$((processed_accounts + 1))
          else
            failures=$((failures + 1))
          fi

          unset MAIL_CLASSIFIER_ACCOUNT_ID MAIL_CLASSIFIER_IMAP_HOST
          unset MAIL_CLASSIFIER_IMAP_PORT MAIL_CLASSIFIER_IMAP_USERNAME
          unset MAIL_CLASSIFIER_IMAP_PASSWORD
          unset localpart password imap_host imap_port username
        done
      done < "$mailbox_set_env_path_list"

      echo "mail-classifier: processed $processed_accounts account(s); failures=$failures"
      [ "$failures" -eq 0 ]
    '';
  };
in
{
  options.profiles.mail.classifier = {
    enable = lib.mkEnableOption "move-only IMAP classification through Ollama";

    mailboxSetAllowList = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Generic mailbox-set ids to process. An empty list processes every discovered hosted mailbox set.";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Classify and log decisions without creating folders or moving messages.";
    };

    sharedNamespacePrefix = lib.mkOption {
      type = lib.types.str;
      default = "s/";
      description = "IMAP prefix whose direct selectable children are shared inboxes.";
    };

    maxMessagesPerMailbox = lib.mkOption {
      type = lib.types.ints.positive;
      default = 25;
      description = "Maximum messages processed from each private or shared inbox per run.";
    };

    maximumBodyCharacters = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16000;
      description = "Maximum decoded text characters sent to Ollama per message.";
    };

    minimumConfidence = lib.mkOption {
      type = lib.types.numbers.between 0 1;
      default = 0.62;
      description = "Classification confidence below which a message is moved to the review destination.";
    };

    lowConfidenceLabel = lib.mkOption {
      type = lib.types.str;
      default = "review";
      readOnly = true;
      description = "Fixed label used for low-confidence classifications.";
    };

    destinations = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = {
        junk = "Junk";
        action = "Sorted/Action";
        finance = "Sorted/Finance";
        receipt = "Sorted/Receipts";
        account = "Sorted/Accounts";
        newsletter = "Sorted/Newsletters";
        notification = "Sorted/Notifications";
        personal = "Sorted/Personal";
        other = "Sorted/Other";
        review = "Sorted/Review";
      };
      description = "Fixed classifier labels and their move-only IMAP destinations.";
    };

    feedbackMailbox = lib.mkOption {
      type = lib.types.str;
      default = "Drafts/Classifier Feedback";
      readOnly = true;
      description = "Subscribed mailbox containing internal per-message classifier feedback drafts.";
    };

    replyMailbox = lib.mkOption {
      type = lib.types.str;
      default = "Drafts/Classifier Replies";
      readOnly = true;
      description = "Subscribed mailbox containing ready-to-review replies for legitimate human mail.";
    };

    imapTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "IMAP connect and operation timeout.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* *:*:00";
      description = "Systemd calendar expression used to inspect mailboxes.";
    };

    timer.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the every-minute mailbox classifier timer is enabled.";
    };

    ollama = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://192.168.3.108:11434";
        description = "Ollama HTTP API base URL.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "qwen3.5:9b-q4_K_M";
        description = "Exact Ollama model that must already be present on the inference server.";
      };

      timeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = "Maximum time for each Ollama HTTP operation.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = mailboxSets != null;
        message = "profiles.mail.classifier requires profiles.nixos.mail.mailbox-sets.";
      }
      {
        assertion = builtins.hasAttr cfg.lowConfidenceLabel cfg.destinations;
        message = "profiles.mail.classifier.lowConfidenceLabel must name a fixed destination.";
      }
      {
        assertion = lib.hasSuffix "/" cfg.sharedNamespacePrefix;
        message = "profiles.mail.classifier.sharedNamespacePrefix must end in '/'.";
      }
      {
        assertion =
          lib.hasPrefix "Drafts/" cfg.feedbackMailbox
          && lib.hasPrefix "Drafts/" cfg.replyMailbox
          && cfg.feedbackMailbox != cfg.replyMailbox;
        message = "profiles.mail.classifier draft mailboxes must be distinct children of Drafts/.";
      }
    ];

    users.groups.${group} = { };
    users.users.${user} = {
      isSystemUser = true;
      inherit group;
    };

    sops.secrets = classifierSecrets;

    systemd.services.${serviceName} = {
      description = "Classify IMAP inboxes and move messages to fixed folders";
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      wants = [ "network-online.target" ];
      preStart = requireReadableSecrets;
      serviceConfig = {
        Type = "oneshot";
        User = user;
        Group = group;
        ExecStart = lib.getExe runner;
        LockPersonality = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
      };
    };

    systemd.timers.${serviceName} = lib.mkIf cfg.timer.enable {
      description = "Inspect hosted IMAP inboxes every minute";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        AccuracySec = "1s";
        RandomizedDelaySec = "5s";
        Persistent = true;
      };
    };

    environment.systemPackages = [ classifier ];
    system.extraDependencies = [ classifierValidation ];
  };
}
